require 'fileutils'
require 'csv'
require_relative '../../excel_converter'

describe ExcelConverter::Converter do
  let(:input_folder) { './input_excel' }
  let(:output_folder) { './src/2025' }
  let(:test_excel_file) { File.join(input_folder, '2025-07-16_Form_analiza.xlsx') }
  let(:expected_csv_file) { File.join(output_folder, '2025-07-16_dance.csv') }

  before(:each) do
    FileUtils.mkdir_p(input_folder)
    FileUtils.mkdir_p(output_folder)
    # Create a minimal Excel file with a 'data' sheet and an extra sheet for testing
    require 'write_xlsx'
    workbook = WriteXLSX.new(test_excel_file)
    worksheet_data = workbook.add_worksheet('data')
    worksheet_data.write_row(0, 0, ['A', 'B', 'C'])
    worksheet_data.write_row(1, 0, [1, 2, 3])
    worksheet_other = workbook.add_worksheet('other_sheet')
    worksheet_other.write_row(0, 0, ['X', 'Y', 'Z'])
    worksheet_other.write_row(1, 0, [9, 8, 7])
    workbook.close
  end

  after(:each) do
    FileUtils.rm_f(test_excel_file)
    FileUtils.rm_f(expected_csv_file)
  end

  it 'converts the Excel data sheet to CSV with correct naming' do
    ExcelConverter::Converter.new.send(:process_file, test_excel_file)
    expect(File).to exist(expected_csv_file)
    csv_content = CSV.read(expected_csv_file)
    expect(csv_content[0]).to eq(['A', 'B', 'C'])
    expect(csv_content[1]).to eq(['1', '2', '3'])
  end
end
