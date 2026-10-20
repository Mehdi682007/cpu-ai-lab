#!/usr/bin/env python3
"""Rebuild the standalone installer from reviewed sources; no network required."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
parts=[(root/'installer/head.sh').read_text(encoding='utf-8')]
for name in ('chat.py','index.html','login.html','benchmark.py'):
    parts.extend([f'\ncat > "$APP/{name}" <<\'CPU_AI_PYTHON\'\n',
                  (root/'src'/name).read_text(encoding='utf-8'),'\nCPU_AI_PYTHON\n'])
parts.extend((root/'installer'/name).read_text(encoding='utf-8') for name in ('tail.sh','network.sh','menu.sh'))
(root/'install.sh').write_text('\n'.join(parts),encoding='utf-8',newline='\n')
print('Built install.sh')
