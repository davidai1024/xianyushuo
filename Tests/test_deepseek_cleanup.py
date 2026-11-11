"""Check the opt-in cloud route and fallback without sending network requests."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Engine'))
import deepseek_cleanup
import worker


class DeepSeekCleanupTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.job = dict(id='test', text='嗯，检查 design.md。', models=temp.name, words=['design.md', '未口述的词'],
                        cleanup='structured', cleanup_provider='deepseek', deepseek_api_key='dummy-key')
        checkpoint = patch.object(worker, 'send')
        self.addCleanup(checkpoint.stop)
        self.checkpoint = checkpoint.start()

    @patch.object(deepseek_cleanup.http.client, 'HTTPSConnection')
    def test_only_transcript_and_relevant_spelling_leave_worker(self, connection):
        response = connection.return_value.getresponse.return_value
        response.status = 200
        response.read.return_value = json.dumps({'choices': [
            {'finish_reason': 'stop', 'message': {'content': '检查 design.md。'}}
        ]}).encode()
        result = worker.process(self.job)
        self.assertEqual(result['output'], '检查 design.md。')
        self.assertEqual(result['metadata']['deepseek_cleanup']['thinking'], 'disabled')
        self.assertEqual(connection.call_args.args[0], 'api.deepseek.com')
        method, path, body, headers = connection.return_value.request.call_args.args
        self.assertEqual((method, path), ('POST', '/chat/completions'))
        self.assertEqual(headers['Authorization'], 'Bearer dummy-key')
        data = json.loads(body)
        self.assertEqual(data['thinking'], {'type': 'disabled'})
        self.assertIn('Markdown', data['messages'][0]['content'])
        self.assertEqual(json.loads(data['messages'][1]['content']),
                         {'transcript': self.job['text'], '保留原文已有的写法': ['design.md']})
        self.assertNotIn('dummy-key', repr(result) + repr(self.checkpoint.call_args_list))

    @patch.object(deepseek_cleanup, 'edit', side_effect=deepseek_cleanup.DeepSeekError('http_401'))
    def test_failure_preserves_text_without_local_weights(self, edit):
        result = worker.process(self.job)
        self.assertEqual(result['output'], self.job['text'])
        self.assertEqual(result['metadata']['deepseek_cleanup'], {'reason': 'http_401', 'fallback': 'raw'})
        edit.assert_called_once()

    @patch.object(deepseek_cleanup, 'edit', side_effect=deepseek_cleanup.DeepSeekError('connection_failed'))
    @patch.object(worker, 'load')
    @patch.object(worker, 'structure', return_value=('本地结果', {}))
    @patch('cleanup_pipeline.cleanup', return_value=('本地结果', {'used_model': True}))
    def test_failure_can_use_local_model(self, cleanup, structure, load, edit):
        (Path(self.job['models']) / 'Qwen3-1.7B-4bit').mkdir()
        result = worker.process(self.job)
        self.assertEqual(result['output'], '本地结果')
        self.assertEqual(result['metadata']['deepseek_cleanup']['fallback'], 'local')
        load.assert_called()
        structure.assert_called_once()
        cleanup.assert_called_once()

    @patch.object(deepseek_cleanup, 'edit', side_effect=AssertionError('Unexpected remote request'))
    def test_disabled_and_local_routes_do_not_call_cloud(self, edit):
        self.assertEqual(worker.process(dict(self.job, cleanup='none'))['output'], self.job['text'])
        with patch('cleanup_pipeline.cleanup', return_value=('本地结果', {})), patch.object(worker, 'load'):
            self.assertEqual(worker.process(dict(self.job, cleanup_provider='local', cleanup='light'))['output'], '本地结果')
        edit.assert_not_called()


if __name__ == '__main__':
    unittest.main()
