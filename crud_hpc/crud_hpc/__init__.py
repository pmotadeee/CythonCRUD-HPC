"""
CRUD HPC

Achieving 1M + opeations/second with sub-millisecond latency
"""

__version__ = "1.0.0"

from crud_hpc.core.crud_engine import CythonCRUDEEngine

__all__ = ["CythonCRUDEEngine"]