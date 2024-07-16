"""Generate profile csv files for load generation"""

import pathlib
import sys
import argparse
import matplotlib.pyplot as plt
import numpy as np


def cli() -> argparse.ArgumentParser:
    """Parse cli arguments."""

    parser = argparse.ArgumentParser(description="Generate CSV profile files.")
    sub = parser.add_subparsers(
        title="command", description="profile type", dest="command"
    )
    parser.add_argument(
        "--output",
        "-o",
        type=pathlib.Path,
        required=True,
        help="Path of the output file",
    )
    linear_parser = sub.add_parser("linear", help="Generate a linear profile.")
    linear_parser.add_argument(
        "--min",
        type=int,
        required=True,
        help="Minimum RPS",
    )
    linear_parser.add_argument(
        "--max",
        type=int,
        required=True,
        help="Maximum RPS",
    )
    linear_parser.add_argument(
        "--duration",
        "-d",
        type=int,
        required=True,
        help="Profile duration (in seconds)",
    )
    step_parser = sub.add_parser("step", help="Generate a step profile.")
    step_parser.add_argument(
        "--rps",
        type=int,
        required=True,
        help="Start RPS",
    )
    step_parser.add_argument(
        "--steps",
        type=int,
        required=True,
        help="Number of steps",
    )
    step_parser.add_argument(
        "--increase",
        type=int,
        required=True,
        help="RPS increase per step",
    )
    step_parser.add_argument(
        "--repeats",
        type=int,
        required=True,
        help="Step repeats",
    )
    step_parser.add_argument(
        "--step-duration",
        "-d",
        type=int,
        required=True,
        help="Step duration (in seconds)",
    )
    return parser


def generate_linear(min_rps: int, max_rps: int, duration: int) -> list[int]:
    """Generate linear profile."""

    return np.rint(np.linspace(min_rps, max_rps, duration)).tolist()


def generate_stepwise(
    start_rps: int, steps: int, increase: int, repeats: int, step_duration: int
) -> list[int]:
    """Generate stepwise profile."""
    total_step_duration = step_duration * repeats
    profile: list[int] = []
    for step in range(steps):
        current_rps = start_rps + (step * increase)
        profile.extend([current_rps for _ in range(total_step_duration)])
    return profile


def main():
    parser = cli()
    args = parser.parse_args()
    command = args.command
    output: pathlib.Path = args.output
    if command == "linear":
        min_rps = args.min
        max_rps = args.max
        duration = args.duration
        profile = generate_linear(min_rps=min_rps, max_rps=max_rps, duration=duration)
    elif command == "step":
        start_rps = args.rps
        steps = args.steps
        increase = args.increase
        repeats = args.repeats
        step_duration = args.step_duration
        profile = generate_stepwise(
            start_rps=start_rps,
            steps=steps,
            increase=increase,
            repeats=repeats,
            step_duration=step_duration,
        )
    else:
        parser.print_help(sys.stderr)
        sys.exit(1)

    plt.plot(profile)
    plt.show()
    with output.open(mode="w", encoding="utf-8") as w:
        w.writelines(
            [f"{time}, {load}\n" for time, load in enumerate(profile, start=1)]
        )


if __name__ == "__main__":
    main()
