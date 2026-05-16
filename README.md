# judgment-anomaly-analyzer

Parse and analyze raw competition judgments to detect anomalies based on defined criteria and generate detailed reports.

## Usage

Place Excel files in `./input_excel/`, then run the full conversion and report pipeline:

```bash
bundle install

# Convert Excel files, concatenate CSV files, and generate reports
make

# Run the full pipeline for a specific year
make YEAR=2025

# Run the full pipeline for every year found in input_excel/
make all-years
```

By default, `make` uses the latest year found in matching Excel filenames from `input_excel/`.

## Individual Scripts

### Excel Converter

Use `excel_converter.rb` to convert Excel files to CSV format:

- Converts `YYYY-MM-DD_Form_analiza.xlsx` → `YYYY-MM-DD_dance.csv`
- Converts `YYYY-MM-DD_Form_acro_analiza.xlsx` → `YYYY-MM-DD_acro.csv`
- Extracts data from the 'data' sheet in Excel files
- Saves output to the `./src/YYYY/` folder matching the year in the Excel filename prefix

```bash
ruby excel_converter.rb
```

Place Excel files in `./input_excel/` folder before running.

### CSV Concatenator

Use `csv_concatenator.rb` to concatenate CSV files by year and type:

- All `YYYY-MM-DD_acro.csv` files → `YYYY-overall_acro.csv`
- All `YYYY-MM-DD_dance.csv` files → `YYYY-overall_dance.csv`

```bash
# Concatenate files for a specific year
ruby csv_concatenator.rb 2025

# Concatenate files for current year (default)
ruby csv_concatenator.rb
```

### Report Generator

Use `main.rb` to generate report CSV and HTML files for one year:

```bash
# Run analysis for a specific year
ruby main.rb 2025

# Defaults to 2026 if no year is provided
ruby main.rb
```

## GitHub Action: Release Reports

The repository includes a GitHub Action that automatically generates and releases analysis reports.

### Behavior

1. **Detects the most recent year** from the `src/` folder (e.g., if `src/2024/` and `src/2025/` exist, it picks `2025`)
2. **Determines the release version** using the format `{year}.{counter}` where the counter increments for each release within the same year
3. **Runs analysis** only for the most recent year
4. **Creates a GitHub release** with all report and summary CSV files for that year

### Version Examples

| src/ folders       | Existing releases    | Next release |
|--------------------|----------------------|--------------|
| 2024, 2025         | none                 | `2025.1`     |
| 2024, 2025         | `2025.1`             | `2025.2`     |
| 2024, 2025         | `2025.1`, `2025.2`   | `2025.3`     |
| 2024, 2025, 2026   | `2025.3`             | `2026.1`     |

### Usage

Trigger the workflow manually from the GitHub Actions tab using "Run workflow".
