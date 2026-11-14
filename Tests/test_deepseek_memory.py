"""Cloud dictation must not retain or run the optional local editor."""
import gc
import json
import sys
import tempfile
import unittest
import weakref
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Engine'))
import deepseek_cleanup
import streaming_pipeline
import worker


class DeepSeekMemoryTests(unittest.TestCase):
    def setUp(self):
        previous = worker.MODELS.copy(), worker.EDITOR_WARM, worker.ASR_WARM
        def restore():
            worker.MODELS.clear()
            worker.MODELS.update(previous[0])
            worker.EDITOR_WARM, worker.ASR_WARM = previous[1:]
        self.addCleanup(restore)
        worker.MODELS.clear()
        self.asr = object()
        worker.MODELS['asr'] = self.asr
        self.job = dict(models='/fixture', cleanup='structured', cleanup_provider='deepseek',
                        text='嗯，请检查文件。', words=[], deepseek_api_key='dummy-key')
        for target in ['worker.send', 'mlx.core.clear_cache']:
            mock = patch(target)
            mock.start()
            self.addCleanup(mock.stop)

    def test_cloud_and_disabled_startup_skip_editor_and_free_old_weights(self):
        for policy in [dict(cleanup_provider='deepseek'), dict(cleanup='none')]:
            worker.MODELS['cleanup'] = object()
            worker.EDITOR_WARM = True
            worker.ASR_WARM = True
            with patch.object(worker.Path, 'is_dir', return_value=True), \
                 patch.object(worker, 'warm_audio'), patch.object(worker, 'warm_editor') as warm:
                result = worker.prewarm('/fixture', **policy)
            warm.assert_not_called()
            self.assertFalse(result['editor_requested'])
            self.assertFalse(result['editor_resident'])
            self.assertFalse(worker.EDITOR_WARM)
            self.assertEqual(worker.MODELS, {'asr': self.asr})

    def test_settings_change_releases_editor_without_waiting_for_dictation(self):
        worker.MODELS['cleanup'] = object()
        worker.EDITOR_WARM = True
        jobs = [json.dumps(dict(id='settings', action='configure_cleanup',
                                cleanup='structured', cleanup_provider='deepseek')).encode()]
        with patch.object(worker, 'protocol_lines', return_value=iter(jobs)), \
             patch.object(worker, 'warm_editor') as warm:
            worker.main()
        self.assertEqual(worker.MODELS, {'asr': self.asr})
        self.assertFalse(worker.EDITOR_WARM)
        warm.assert_not_called()

    def test_release_also_drops_instruction_caches(self):
        class Editor: pass
        model = Editor()
        model._dictation_prefixes = {'synthetic': object()}
        reference = weakref.ref(model)
        worker.MODELS['cleanup'] = (model, object())
        del model
        worker.release_editor()
        gc.collect()
        self.assertIsNone(reference())
        self.assertIs(worker.MODELS['asr'], self.asr)

    def test_cloud_success_never_loads_or_runs_local_editor(self):
        worker.MODELS['cleanup'] = object()
        with patch.object(deepseek_cleanup, 'edit', return_value=('请检查文件。', .1)), \
             patch.object(worker, 'load') as load, patch('cleanup_pipeline.cleanup') as cleanup:
            result = worker.process(self.job)
        self.assertEqual(result['output'], '请检查文件。')
        load.assert_not_called()
        cleanup.assert_not_called()
        self.assertNotIn('cleanup', worker.MODELS)

    def test_fallback_weights_are_released_on_success_and_failure(self):
        def load(role, root):
            worker.MODELS[role] = object()
            return worker.MODELS[role]
        for failure in [False, True]:
            with patch.object(worker.Path, 'is_dir', return_value=True), \
                 patch.object(deepseek_cleanup, 'edit', side_effect=deepseek_cleanup.DeepSeekError('connection_failed')), \
                 patch.object(worker, 'load', side_effect=load), \
                 patch('cleanup_pipeline.cleanup', return_value=('请检查文件。', {}),
                       side_effect=RuntimeError('synthetic failure') if failure else None), \
                 patch.object(worker, 'structure', return_value=('请检查文件。', {})):
                result = worker.process(self.job)
            self.assertEqual(result['output'], self.job['text'] if failure else '请检查文件。')
            self.assertNotIn('cleanup', worker.MODELS)
            self.assertIs(worker.MODELS['asr'], self.asr)

    def test_local_editor_stays_resident_when_switching_back(self):
        editor = object()
        def load(role, root):
            worker.MODELS[role] = editor
            return editor
        with patch.object(worker, 'load', side_effect=load), \
             patch('cleanup_pipeline.should_bypass', return_value=False), \
             patch('cleanup_pipeline.cleanup', return_value=('请检查文件。', {})):
            worker.process(dict(self.job, cleanup_provider='local', cleanup='light'))
        self.assertIs(worker.MODELS['cleanup'], editor)

    def test_cloud_chunk_only_runs_asr_even_if_caller_requests_structured_edit(self):
        import numpy as np
        import soundfile as sf
        with tempfile.TemporaryDirectory() as folder:
            audio = Path(folder) / 'synthetic.wav'
            sf.write(audio, np.ones(16000, dtype='float32') * .1, 16000)
            job = dict(self.job, audio=str(audio), recording_id='synthetic', start_frame=0,
                       frame_count=16000, sample_rate=16000)
            with patch.object(worker, 'load', return_value=self.asr) as load, \
                 patch('asr_pipeline.recognize', return_value=('请检查文件。', {'segments': []})), \
                 patch('cleanup_pipeline.cleanup') as cleanup, \
                 patch.object(deepseek_cleanup, 'edit') as cloud:
                result = worker.process_chunk(job)
            self.addCleanup(streaming_pipeline.discard, 'synthetic')
            load.assert_called_once_with('asr', '/fixture')
            cleanup.assert_not_called()
            cloud.assert_not_called()
            self.assertIsNone(streaming_pipeline.CACHE[result['ticket']]['cleaned'])
            with patch.object(worker, 'load', return_value=self.asr) as load, \
                 patch('asr_pipeline.recognize') as decode, \
                 patch('cleanup_pipeline.cleanup') as cleanup, \
                 patch.object(deepseek_cleanup, 'edit', return_value=('请检查文件。', .1)) as cloud:
                final = worker.process(dict(job, streaming_tickets=[result['ticket']]))
            self.assertEqual(final['output'], '请检查文件。')
            self.assertEqual(final['metadata']['streaming_reuse'], 'verified_exact_pcm_coverage')
            load.assert_called_once_with('asr', '/fixture')
            decode.assert_not_called()
            cleanup.assert_not_called()
            cloud.assert_called_once()
            # Defense in depth for direct callers that pass an editor anyway.
            with patch('cleanup_pipeline.cleanup') as cleanup:
                streaming_pipeline.pretranscribe(job, self.asr, [],
                    lambda *args, **kw: ('请检查文件。', {'segments': []}), object())
            cleanup.assert_not_called()


if __name__ == '__main__':
    unittest.main()
