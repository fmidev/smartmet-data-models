#!/usr/bin/env python3
"""
download_ecmwf_opendata.py

Download ECMWF real-time open data using the ecmwf-opendata package.

Features:
- Choose download source: ecmwf, aws, azure, google
- Choose model (ifs / aifs-single / aifs-ens)
- Choose resolution keyword (resol)
- Choose forecast length via --steps or via --max-step + --step
- Choose surface (sfc) or pressure levels (pl) with --levelist
- Choose parameters via --param (comma-separated)
- Optional retries with exponential backoff + optional request timeout

Install:
  pip install ecmwf-opendata
"""

import argparse
import os
import sys
import time
from typing import List, Optional, Sequence, Union

from ecmwf.opendata import Client


def parse_csv_list(s):
    return [x.strip() for x in s.split(",") if x.strip()]

def parse_steps(steps_str):
    """
    Supports:
      - "0,3,6"
      - "0:144:3"
      - "0:144:3,150:240:6"  (multiple ranges)
    Returns sorted unique integer steps.
    """
    tokens = [t.strip() for t in steps_str.split(",") if t.strip()]
    steps = set()

    for token in tokens:
        if ":" in token:
            parts = [p.strip() for p in token.split(":")]
            if len(parts) == 3 and all(p.lstrip("-").isdigit() for p in parts):
                start, end, inc = map(int, parts)
                if inc <= 0:
                    raise ValueError("Invalid increment in step range: {}".format(token))
                if end < start:
                    raise ValueError("Invalid range (end < start): {}".format(token))
                for s in range(start, end + 1, inc):
                    steps.add(s)
                continue

        if token.lstrip("-").isdigit():
            steps.add(int(token))
            continue

        raise ValueError("Unrecognized step token: {}".format(token))

    if not steps:
        raise ValueError("No steps parsed from --steps")

    return sorted(steps)

def generate_steps(max_step, base_step):
    if base_step <= 0:
        raise ValueError("--step must be > 0")
    if max_step < 0:
        raise ValueError("--max-step must be >= 0")
    return list(range(0, max_step + 1, base_step))


def build_arg_parser():
    p = argparse.ArgumentParser(
        description="Download ECMWF open-data forecasts with ecmwf-opendata.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    # Where to download from
    p.add_argument(
        "--source",
        default="ecmwf",
        choices=["ecmwf", "aws", "azure", "google"],
        help="Download source/mirror.",
    )

    # Model options
    p.add_argument(
        "--model",
        default="ifs",
        choices=["ifs", "aifs-single", "aifs-ens"],
        help="Model producing the data.",
    )

    # Resolution keyword used by Client
    p.add_argument(
        "--resol",
        default="0p25",
        help="Resolution keyword for Client (open-data commonly provides 0p25).",
    )

    # Forecast identification
    p.add_argument("--type", default="fc", help="Data type (e.g., fc, cf, pf, em, es, ep, tf).")
    p.add_argument("--stream", default=None, help="Forecasting system stream (optional).")
    p.add_argument(
        "--date",
        default=None,
        help="Forecast start date/time. Safer on older Python: use YYYYMMDD (e.g. 20260130). "
             "If omitted, client may try to pick latest (may fail on Python 3.6 depending on library version).",
    )
    p.add_argument(
        "--time",
        type=int,
        default=None,
        help="Forecast cycle hour in UTC (commonly 0, 6, 12, 18).",
    )

    # Forecast length
    group = p.add_mutually_exclusive_group()
    group.add_argument(
        "--steps",
        default=None,
        help="Explicit steps. Examples: '0,3,6,9,12' or '0:240:3' or '0-24,12-36,24-48'.",
    )
    group.add_argument(
        "--max-step",
        type=int,
        default=240,
        help="Max forecast step (hours) when generating steps with --step.",
    )
    p.add_argument(
        "--step",
        type=int,
        default=3,
        help="Step increment (hours) used with --max-step (ignored if --steps is provided).",
    )

    # Field selection
    p.add_argument(
        "--param",
        required=True,
        help="Parameter(s), comma-separated. Example: 'msl' or '2t,msl' or 'u,v'.",
    )
    p.add_argument(
        "--levtype",
        default="sfc",
        choices=["sfc", "pl"],
        help="Surface ('sfc') or pressure levels ('pl').",
    )
    p.add_argument(
        "--levelist",
        default=None,
        help="Pressure level(s) in hPa if levtype=pl. Example: '850' or '1000,850,500'.",
    )

    # Output
    p.add_argument(
        "--target",
        default="ecmwf_data.grib2",
        help="Output GRIB2 file path.",
    )

    # Retry/timeout controls
    p.add_argument("--retries", type=int, default=2, help="Number of retries after the first attempt.")
    p.add_argument("--retry-wait", type=float, default=5.0, help="Initial wait (seconds) before retrying.")
    p.add_argument("--retry-backoff", type=float, default=2.0, help="Backoff factor applied each retry.")
    p.add_argument("--retry-max-wait", type=float, default=60.0, help="Maximum wait (seconds) between retries.")
    p.add_argument(
        "--timeout",
        type=float,
        default=None,
        help="HTTP request timeout in seconds (passed to underlying requests). If omitted, library default is used.",
    )
    p.add_argument(
        "--cleanup-partial",
        action="store_true",
        help="Remove target file if an attempt fails (useful if partial downloads occur).",
    )

    return p


def retrieve_with_retry(client, request, target, retries, retry_wait, retry_backoff, retry_max_wait, timeout, cleanup_partial):
    attempts = retries + 1
    wait_s = retry_wait

    last_exc = None
    for i in range(attempts):
        try:
            kwargs = {}
            if timeout is not None:
                kwargs["timeout"] = timeout

            return client.retrieve(request=request, target=target, **kwargs)

        except Exception as e:
            last_exc = e
            attempt_no = i + 1

            # Cleanup partial file if requested
            if cleanup_partial:
                try:
                    if os.path.exists(target):
                        os.remove(target)
                except Exception:
                    pass

            if attempt_no >= attempts:
                break

            # Sleep then retry
            sleep_for = min(wait_s, retry_max_wait)
            print(
                "Download failed (attempt {}/{}): {}. Retrying in {:.1f}s...".format(
                    attempt_no, attempts, repr(e), sleep_for
                ),
                file=sys.stderr,
            )
            time.sleep(sleep_for)
            wait_s *= retry_backoff

    # Out of attempts
    raise last_exc


def main(argv=None):
    args = build_arg_parser().parse_args(argv)

    params = parse_csv_list(args.param)
    if not params:
        print("ERROR: --param is empty after parsing.", file=sys.stderr)
        return 2

    request = {
        "type": args.type,
        "param": params if len(params) > 1 else params[0],
    }

    if args.stream is not None:
        request["stream"] = args.stream

    # date/time optional
    if args.date is not None:
        request["date"] = args.date
    if args.time is not None:
        request["time"] = args.time

    # steps
    try:
        if args.steps:
            request["step"] = parse_steps(args.steps)
        else:
            request["step"] = generate_steps(args.max_step, args.step)
    except ValueError as e:
        print("ERROR parsing steps: {}".format(e), file=sys.stderr)
        return 2

    # levels
    if args.levtype == "pl":
        request["levtype"] = "pl"
        if not args.levelist:
            print("ERROR: --levelist is required when --levtype pl", file=sys.stderr)
            return 2
        levels_raw = parse_csv_list(args.levelist)
        try:
            levels = [int(x) for x in levels_raw]
        except ValueError:
            print("ERROR: --levelist must be integers (hPa), comma-separated.", file=sys.stderr)
            return 2
        request["levelist"] = levels if len(levels) > 1 else levels[0]
    else:
        request["levtype"] = "sfc"

    client = Client(source=args.source, model=args.model, resol=args.resol)

    os.makedirs(os.path.dirname(os.path.abspath(args.target)) or ".", exist_ok=True)

    print("Download source:", args.source)
    print("Request:", request)
    print("Downloading to:", args.target)

    try:
        result = retrieve_with_retry(
            client=client,
            request=request,
            target=args.target,
            retries=args.retries,
            retry_wait=args.retry_wait,
            retry_backoff=args.retry_backoff,
            retry_max_wait=args.retry_max_wait,
            timeout=args.timeout,
            cleanup_partial=args.cleanup_partial,
        )
    except Exception as e:
        print("ERROR: Download failed after retries: {}".format(repr(e)), file=sys.stderr)
        return 1

    if hasattr(result, "datetime"):
        print("Retrieved forecast run datetime (UTC):", result.datetime)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
