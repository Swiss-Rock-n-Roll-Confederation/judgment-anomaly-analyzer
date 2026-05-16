.DEFAULT_GOAL := all

INPUT_YEARS := $(shell ruby -e 'years = Dir.glob("input_excel/*.xlsx").map { |path| File.basename(path)[/\A(\d{4})-\d{2}-\d{2}_Form_(?:acro_)?analiza\.xlsx\z/, 1] }.compact.uniq.sort; print years.join(" ")')
YEAR ?= $(if $(INPUT_YEARS),$(lastword $(INPUT_YEARS)),$(shell date +%Y))

.PHONY: all pipeline convert concatenate analyze reports all-years test help

all: pipeline

pipeline: analyze

convert:
	bundle exec ruby excel_converter.rb

concatenate: convert
	bundle exec ruby csv_concatenator.rb $(YEAR)

analyze: concatenate
	bundle exec ruby main.rb $(YEAR)

reports: pipeline

all-years: convert
	@if [ -z "$(INPUT_YEARS)" ]; then \
		echo "No input Excel years found in input_excel/"; \
		exit 1; \
	fi
	@for year in $(INPUT_YEARS); do \
		echo "==> Concatenating $$year"; \
		bundle exec ruby csv_concatenator.rb $$year; \
		echo "==> Generating reports for $$year"; \
		bundle exec ruby main.rb $$year; \
	done

test:
	bundle exec rspec

help:
	@echo "Usage:"
	@echo "  make                 Run convert, concatenate, and analyze for YEAR=$(YEAR)"
	@echo "  make YEAR=2025      Run the full pipeline for a specific year"
	@echo "  make all-years      Run the full pipeline for every year found in input_excel/"
	@echo "  make convert        Convert Excel files into src/{YEAR}/ CSV files"
	@echo "  make concatenate    Rebuild overall CSV files for YEAR=$(YEAR)"
	@echo "  make analyze        Generate reports for YEAR=$(YEAR)"
	@echo "  make test           Run the RSpec suite"
