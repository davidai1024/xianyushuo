"""Bounded Metal residency for the ASR model, without background inference."""
MIB = 1024 ** 2
GIB = 1024 ** 3


def residency_budget(info):
    """Leave at least two thirds of unified memory outside this wired budget."""
    total = int(info.get('memory_size', 0))
    recommended = int(info.get('max_recommended_working_set_size', 0))
    if total <= 0 or recommended <= 0:
        return 0
    return max(0, min(3 * GIB, total // 3, recommended))


def configure(mx):
    """Call on the worker's serial execution thread before model allocation."""
    if not mx.metal.is_available():
        return {'enabled': False, 'reason': 'metal_unavailable'}
    try:
        budget = residency_budget(mx.device_info())
        if not budget:
            return {'enabled': False, 'reason': 'missing_memory_budget'}
        mx.synchronize()
        mx.set_wired_limit(budget)
        # Free buffers must not crowd the persistent ASR weights out of the
        # residency budget. This bounds reuse, not active inference allocations.
        mx.set_cache_limit(128 * MIB)
        return {'enabled': True, 'wired_limit_bytes': budget,
                'cache_limit_bytes': 128 * MIB, 'refresh_interval_ms': 1000}
    except (AttributeError, RuntimeError, ValueError):
        # macOS 14 / unsupported Metal devices keep the existing inference path.
        return {'enabled': False, 'reason': 'residency_unavailable'}
