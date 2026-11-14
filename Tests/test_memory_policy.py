import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Engine'))
import memory_policy as policy
import worker


class MemoryPolicyTests(unittest.TestCase):
    def test_budget_leaves_memory_for_other_apps_and_respects_device_cap(self):
        for gb in [4, 8, 16, 32, 128]:
            for recommended in [1, 2, 12, 64]:
                info = dict(memory_size=gb * policy.GIB,
                            max_recommended_working_set_size=recommended * policy.GIB)
                size = policy.residency_budget(info)
                self.assertLessEqual(size, 3 * policy.GIB)
                self.assertLessEqual(size, info['memory_size'] // 3)
                self.assertLessEqual(size, info['max_recommended_working_set_size'])
        self.assertEqual(policy.residency_budget({}), 0)
        self.assertEqual(policy.residency_budget(dict(memory_size=-1)), 0)

    def test_synchronize_before_residency_change_and_limit_free_cache(self):
        mx = Mock()
        mx.device_info.return_value = dict(memory_size=16 * policy.GIB,
                                          max_recommended_working_set_size=12 * policy.GIB)
        result = policy.configure(mx)
        self.assertTrue(result['enabled'])
        self.assertEqual(mx.method_calls, [
            unittest.mock.call.metal.is_available(), unittest.mock.call.device_info(),
            unittest.mock.call.synchronize(), unittest.mock.call.set_wired_limit(3 * policy.GIB),
            unittest.mock.call.set_cache_limit(128 * policy.MIB)])

    def test_unsupported_devices_keep_inference_available(self):
        mx = Mock()
        mx.metal.is_available.return_value = False
        self.assertFalse(policy.configure(mx)['enabled'])
        mx.set_wired_limit.assert_not_called()
        mx.metal.is_available.return_value = True
        mx.device_info.return_value = dict(memory_size=16 * policy.GIB,
                                          max_recommended_working_set_size=12 * policy.GIB)
        mx.set_wired_limit.side_effect = RuntimeError('unsupported device')
        self.assertFalse(policy.configure(mx)['enabled'])

    def test_refresh_is_enabled_before_importing_mlx(self):
        import os, subprocess, json
        code = "import sys,os,json;sys.path.insert(0,sys.argv[1]);import worker;print(json.dumps([os.environ['MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS'],'mlx.core' in sys.modules]))"
        output = subprocess.check_output([sys.executable, '-B', '-c', code,
            str(Path(worker.__file__).parent)], env={**os.environ,
            'MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS': '0'}, text=True)
        self.assertEqual(json.loads(output), ['1000', False])

    def test_streaming_allocates_asr_before_editor(self):
        with patch.object(worker, 'load', side_effect=lambda role, root: role) as load, \
             patch('streaming_pipeline.pretranscribe', return_value={'ticket': 'synthetic'}) as decode:
            worker.process_chunk(dict(models='/synthetic', words=[], cleanup='light'))
        self.assertEqual([call.args[0] for call in load.call_args_list], ['asr', 'cleanup'])
        self.assertEqual(decode.call_args.args[1], 'asr')
        self.assertEqual(decode.call_args.args[-1], 'cleanup')

    def test_worker_configures_once_not_per_dictation(self):
        old = worker.MEMORY_POLICY
        try:
            worker.MEMORY_POLICY = None
            with patch.object(policy, 'configure', return_value={'enabled': True}) as configure:
                worker.configure_memory()
                worker.configure_memory()
            configure.assert_called_once()
        finally:
            worker.MEMORY_POLICY = old
