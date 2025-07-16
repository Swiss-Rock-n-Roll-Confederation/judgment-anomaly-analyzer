require 'roo'
require 'csv'
require 'fileutils'

module ExcelConverter
  INPUT_FOLDER = "./input_excel"  # Where your Excel files are stored
  OUTPUT_FOLDER = "./src"         # Where to save the CSV files
  YEAR = "2025"                   # Current year for output folder

  class Converter
    def self.run
      new.run
    end

    def run
      ensure_directories_exist
      process_excel_files
    end

    private

    def ensure_directories_exist
      FileUtils.mkdir_p(INPUT_FOLDER) unless Dir.exist?(INPUT_FOLDER)
      output_folder = File.join(OUTPUT_FOLDER, YEAR)
      FileUtils.mkdir_p(output_folder) unless Dir.exist?(output_folder)
    end

    def process_excel_files
      excel_files = Dir.glob(File.join(INPUT_FOLDER, "*.xlsx"))
      if excel_files.empty?
        puts "❌ No Excel files found in #{INPUT_FOLDER}"
        return
      end

      excel_files.each do |file_path|
        process_file(file_path)
      end
    end

    def process_file(file_path)
      filename = File.basename(file_path)
      
      # Extract date and determine file type
      if filename =~ /^(\d{4}-\d{2}-\d{2})_Form_analiza\.xlsx$/
        date = $1
        output_type = "dance"
      elsif filename =~ /^(\d{4}-\d{2}-\d{2})_Form_acro_analiza\.xlsx$/
        date = $1
        output_type = "acro"
      else
        puts "❌ Skipping file with unrecognized naming pattern: #{filename}"
        return
      end
      
      begin
        # Open Excel file and extract 'data' sheet
        excel = Roo::Excelx.new(file_path)
        
        if !excel.sheets.include?("data")
          puts "❌ No 'data' sheet found in #{filename}"
          return
        end
        
        excel.default_sheet = "data"
        
        # Output path
        output_path = File.join(OUTPUT_FOLDER, YEAR, "#{date}_#{output_type}.csv")
        
        # Convert to CSV
        CSV.open(output_path, "wb") do |csv|
          1.upto(excel.last_row) do |row|
            csv << excel.row(row)
          end
        end
        
        puts "✅ Converted #{filename} to #{File.basename(output_path)}"
      rescue => e
        puts "❌ Error processing #{filename}: #{e.message}"
      end
    end
  end
end

if __FILE__ == $0
  ExcelConverter::Converter.run
end