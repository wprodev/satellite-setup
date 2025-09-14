from dataclasses import dataclass, field
from pathlib import Path
from threading import Lock, Semaphore, Thread
from typing import Dict, List, Optional

from .const import ClientData


@dataclass
class WakeWordState:
    embeddings_ready: Semaphore = field(default_factory=Semaphore)
    embeddings_lock: Lock = field(default_factory=Lock)


@dataclass
class State:
    models_dir: Path
    """Directory with built-in models."""

    custom_model_dirs: List[Path] = field(default_factory=list)
    """Directories with custom wake word models."""

    ww_threads: Dict[str, Thread] = field(default_factory=dict)
    ww_threads_lock: Lock = field(default_factory=Lock)

    is_running: bool = True
    clients: Dict[str, ClientData] = field(default_factory=dict)
    clients_lock: Lock = field(default_factory=Lock)

    audio_ready: Semaphore = field(default_factory=Semaphore)
    audio_lock: Lock = field(default_factory=Lock)

    mels_ready: Semaphore = field(default_factory=Semaphore)
    mels_lock: Lock = field(default_factory=Lock)

    # full name -> state
    wake_words: Dict[str, WakeWordState] = field(default_factory=dict)

    # alias -> full name
    wake_word_aliases: Dict[str, str] = field(default_factory=dict)

    debug_probability: bool = False
    output_dir: Optional[Path] = None
