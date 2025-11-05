require 'csv'
require 'fileutils'

module CSVConcatenator
  class Concatenator
    def self.run(year = nil)
      new.run(year)
    end

    def run(year = nil)
      # If no year specified, use current year
      year ||= Date.today.year.to_s
      
      src_folder = "./src/#{year}"
      
      unless Dir.exist?(src_folder)
        puts "❌ Source folder #{src_folder} does not exist"
        return
      end

      puts "📁 Processing CSV files in #{src_folder}"
      
      # Process acro files
      concatenate_files(src_folder, year, 'acro')
      
      # Process dance files
      concatenate_files(src_folder, year, 'dance')
    end

    private

    def concatenate_files(src_folder, year, file_type)
      pattern = File.join(src_folder, "*_#{file_type}.csv")
      files = Dir.glob(pattern).reject { |f| f.include?('overall') }.sort
      
      if files.empty?
        puts "⚠️  No #{file_type} files found matching pattern: #{pattern}"
        return
      end

      output_file = File.join(src_folder, "#{year}-overall_#{file_type}.csv")
      
      puts "\n🔄 Processing #{file_type} files:"
      files.each { |file| puts "  - #{File.basename(file)}" }

      header_written = false
      total_rows = 0

      CSV.open(output_file, "wb") do |output_csv|
        files.each do |file_path|
          process_file(file_path, output_csv, header_written) do |rows_added|
            total_rows += rows_added
            header_written = true if rows_added > 0
          end
        end
      end

      puts "✅ Successfully created #{File.basename(output_file)}"
      puts "📊 Total rows: #{total_rows} (excluding header)"
    end

    def process_file(file_path, output_csv, skip_header)
      filename = File.basename(file_path)
      rows_added = 0

      begin
        CSV.foreach(file_path, headers: false).with_index do |row, index|
          # Skip header row if not the first file
          next if index == 0 && skip_header
          
          output_csv << row
          rows_added += 1
        end

        puts "  ✅ Processed #{filename}: #{rows_added} rows"
      rescue => e
        puts "  ❌ Error processing #{filename}: #{e.message}"
      end

      yield(rows_added) if block_given?
    end
  end
end

if __FILE__ == $0
  require 'date'
  
  # Parse command line arguments
  year = ARGV[0]
  
  if year && !year.match?(/^\d{4}$/)
    puts "Usage: ruby csv_concatenator.rb [YYYY]"
    puts "Example: ruby csv_concatenator.rb 2025"
    exit 1
  end
  
  CSVConcatenator::Concatenator.run(year)
end