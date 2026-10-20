#!/usr/bin/env python3
"""Repeatable streaming CPU benchmark. Writes responses and measured statistics."""
import argparse
import datetime
import json
import os
import platform
import subprocess
import threading
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("--models", nargs="+", default=[os.environ.get("CPU_AI_MODEL", "qwen2.5:0.5b")])
parser.add_argument("--repeats", type=int, default=3)
parser.add_argument("--output", default="benchmark-results.json")
args = parser.parse_args()
if not 1 <= args.repeats <= 10:
    parser.error("repeats must be 1..10")
tests = [
    ("persian", "به فارسی و در سه جمله ساده توضیح بده تفاوت RAM و فضای دیسک چیست."),
    ("summary", "این متن را در یک جمله فارسی خلاصه کن: یک فروشگاه اینترنتی هر شب از پایگاه داده خود نسخه پشتیبان تهیه می‌کند. نسخه‌ها روی سرور دیگری نگهداری می‌شوند. مدیر فروشگاه هر هفته بازیابی نسخه پشتیبان را آزمایش می‌کند تا از سالم بودن اطلاعات مطمئن شود."),
    ("bash", "Write a short Bash script that prints a warning if root filesystem disk usage exceeds 80 percent. Do not delete or modify any files."),
]
def memory():
    with open("/proc/meminfo") as f:
        return {k: int(v.split()[0]) for k, v in (line.split(":", 1) for line in f)}

def post(path, payload):
    if payload.get("model", "").startswith("qwen3"):
        payload["think"] = False
    return urllib.request.urlopen(urllib.request.Request(
        "http://127.0.0.1:11434/api"+path, json.dumps(payload).encode(),
        {"Content-Type": "application/json"}), timeout=300)

report = {"timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
          "platform": platform.platform(), "cpu_count": os.cpu_count(),
          "memory_total_mib": memory()["MemTotal"]/1024,
          "ollama_version": subprocess.check_output(["ollama", "--version"], text=True).strip(),
          "settings": {"num_gpu": 0, "num_ctx": 2048, "num_predict": 128,
                       "num_thread": os.cpu_count(), "temperature": 0, "seed": 42},
          "note": "Memory is whole-system MemAvailable sampled every 100ms; not isolated model RSS. First run per model is cold; later runs are warm. TTFT includes prompt processing.",
          "results": []}
for model in args.models:
    with urllib.request.urlopen("http://127.0.0.1:11434/api/ps", timeout=10) as response:
        for loaded in json.load(response).get("models", []):
            with post("/generate", {"model": loaded["name"], "keep_alive": 0}) as result:
                result.read()
    for repeat in range(args.repeats):
        for name, prompt in tests:
            baseline = memory()["MemAvailable"]
            samples = [baseline]
            stop = threading.Event()
            def sample():
                while not stop.wait(0.1):
                    samples.append(memory()["MemAvailable"])
            sampler = threading.Thread(target=sample, daemon=True)
            sampler.start()
            start = time.perf_counter()
            first = None
            text = ""
            final = {}
            try:
                with post("/generate", {"model": model, "prompt": prompt, "stream": True,
                           "keep_alive": "2m", "options": report["settings"]}) as response:
                    for line in response:
                        event = json.loads(line)
                        if "error" in event:
                            raise RuntimeError(event["error"])
                        if event.get("response"):
                            if first is None:
                                first = time.perf_counter()-start
                            text += event["response"]
                        if event.get("done"):
                            final = event
                if not final:
                    raise RuntimeError("Missing completion event")
            except Exception as exc:
                report.setdefault("errors", []).append({
                    "model": model, "test": name, "repeat": repeat+1,
                    "error": str(exc), "wall_seconds": round(time.perf_counter()-start, 3),
                    "minimum_system_available_mib": round(min(samples)/1024, 1)})
                with open(args.output, "w", encoding="utf-8") as f:
                    json.dump(report, f, ensure_ascii=False, indent=2)
                raise
            finally:
                stop.set()
                sampler.join()
            elapsed = time.perf_counter()-start
            duration = final.get("eval_duration", 0)/1e9
            with urllib.request.urlopen("http://127.0.0.1:11434/api/ps", timeout=10) as response:
                running = json.load(response)
            row = {"model": model, "test": name, "repeat": repeat+1,
                   "cold": repeat == 0 and name == "persian",
                   "thinking_disabled": model.startswith("qwen3"),
                   "wall_seconds": round(elapsed, 3), "ttft_seconds": round(first, 3) if first is not None else None,
                   "tokens": final.get("eval_count", 0), "done_reason": final.get("done_reason"),
                   "tokens_per_second": round(final.get("eval_count", 0)/duration, 2) if duration else 0,
                   "load_seconds": round(final.get("load_duration", 0)/1e9, 3),
                   "minimum_system_available_mib": round(min(samples)/1024, 1),
                   "system_available_drop_mib": round((baseline-min(samples))/1024, 1),
                   "response": text, "loaded_models": running}
            report["results"].append(row)
            with open(args.output, "w", encoding="utf-8") as f:
                json.dump(report, f, ensure_ascii=False, indent=2)
            print(json.dumps({k:v for k,v in row.items() if k not in ("response", "loaded_models")}), flush=True)
