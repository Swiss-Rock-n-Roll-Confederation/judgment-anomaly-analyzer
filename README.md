# judgment-anomaly-analyzer

Parse and analyze raw competition judgments to detect anomalies based on defined criteria and generate detailed reports.

The `main.rb` define the input and output folders.

```
bundle install
ruby main.rb
```

## Excel Converter

Use `excel_converter.rb` to convert Excel files to CSV format:

- Converts `YYYY-MM-DD_Form_analiza.xlsx` → `YYYY-MM-DD_dance.csv`
- Converts `YYYY-MM-DD_Form_acro_analiza.xlsx` → `YYYY-MM-DD_acro.csv`
- Extracts data from the 'data' sheet in Excel files
- Saves output to `./src/YYYY/` folder

```bash
ruby excel_converter.rb
```

Place Excel files in `./input_excel/` folder before running.

## CSV Concatenator

Use `csv_concatenator.rb` to concatenate CSV files by year and type:

- All `YYYY-MM-DD_acro.csv` files → `YYYY-overall_acro.csv`
- All `YYYY-MM-DD_dance.csv` files → `YYYY-overall_dance.csv`

```bash
# Concatenate files for a specific year
ruby csv_concatenator.rb 2025

# Concatenate files for current year (default)
ruby csv_concatenator.rb
```
