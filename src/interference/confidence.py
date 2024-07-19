"""Calculate the confidence interval for each step."""

from collections.abc import Generator
import pathlib
import os
import argparse
import logging
import yaml

import pandas as pd

MEASUREMENTS_DIR: pathlib.Path = pathlib.Path("measurements")
STEP_COLUMN: str = "step"
REPEAT_COLUMN: str = "repeat"
RESPONSE_TIME_COLUMN: str = "response_time"
CONFIDENCE_INTERVAL_LOW_COLUMN: str = "ci95_low"
CONFIDENCE_INTERVAL_HIGH_COLUMN: str = "ci95_high"
CONFIDENCE_INTERVAL_WIDTH: str = "ci95_width"
MEAN: str = "mean"
STANDARD_ERROR_MEAN: str = "sem"
# See: https://stackoverflow.com/questions/53519823/confidence-interval-in-python-dataframe#comment123186350_53522680
MULTIPLIER: float = 1.96

logging.basicConfig()


def cli() -> argparse.ArgumentParser:
    """Parse cli arguments."""

    parser = argparse.ArgumentParser(description="Calculate confidence intervals.")
    parser.add_argument(
        "--benchmark",
        type=str,
        required=True,
        help="Benchmark directory name",
    )
    return parser


def calculate_confidence_intervals(benchmark: str):
    path = MEASUREMENTS_DIR.joinpath(benchmark)
    dfs = []
    for step in yield_all_subdir_names(path):
        step_path = path.joinpath(step)
        for repeat in yield_all_subdir_names(step_path):
            repeat_path = step_path.joinpath(repeat)
            df = pd.read_csv(repeat_path.joinpath("summary_out.csv"))
            df[REPEAT_COLUMN] = repeat
            df[STEP_COLUMN] = step
            df = df.rename(columns={"Avg Response Time": RESPONSE_TIME_COLUMN})
            dfs.append(df.loc[:, [STEP_COLUMN, REPEAT_COLUMN, RESPONSE_TIME_COLUMN]])
    df = pd.concat(dfs, axis="index")
    stats = df.groupby([STEP_COLUMN])[RESPONSE_TIME_COLUMN].agg(
        [MEAN, STANDARD_ERROR_MEAN]
    )
    stats[CONFIDENCE_INTERVAL_HIGH_COLUMN] = (  # type: ignore
        stats[MEAN] + MULTIPLIER * stats[STANDARD_ERROR_MEAN]
    )
    stats[CONFIDENCE_INTERVAL_LOW_COLUMN] = (  # type: ignore
        stats[MEAN] - MULTIPLIER * stats[STANDARD_ERROR_MEAN]
    )
    stats[CONFIDENCE_INTERVAL_WIDTH] = (  # type: ignore
        stats[CONFIDENCE_INTERVAL_HIGH_COLUMN] - stats[CONFIDENCE_INTERVAL_LOW_COLUMN]
    )
    for step in stats.index:
        low = float(stats.at[step, CONFIDENCE_INTERVAL_LOW_COLUMN])
        high = float(stats.at[step, CONFIDENCE_INTERVAL_HIGH_COLUMN])
        width = float(stats.at[step, CONFIDENCE_INTERVAL_WIDTH])
        with path.joinpath(step, "confidence.yml").open(mode="w") as w:  # type: ignore
            yaml.safe_dump({"low": low, "high": high, "width": width}, w)

    # Check CI widths
    repeats = df.groupby([STEP_COLUMN, REPEAT_COLUMN])
    exceeds = {}
    for (step, repeat), group in repeats:  # type: ignore
        width = stats.loc[step, CONFIDENCE_INTERVAL_WIDTH]
        mean = group[RESPONSE_TIME_COLUMN].mean()
        check = 0.05 * mean
        if width > check:
            exceeds.setdefault(step, []).append(f"{repeat} ({check})")

    for step, repeats in exceeds.items():
        width = stats.loc[step, CONFIDENCE_INTERVAL_WIDTH]
        logging.warning(
            "step %s:\nconfidence interval width (%s) exceeds 5%% of sample mean\n%s",
            step,
            width,
            "\n".join(repeats),
        )


def yield_all_subdir_names(p: pathlib.Path) -> Generator[str, None, None]:
    for sub in os.scandir(p):
        if sub.is_dir():
            yield sub.name


def main():
    parser = cli()
    args = parser.parse_args()
    calculate_confidence_intervals(args.benchmark)


if __name__ == "__main__":
    main()
