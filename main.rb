require './module/model/category.rb'
require './module/model/anomaly.rb'
require './module/model/analyse.rb'
require './module/parser.rb'
require './module/analyzer.rb'
require './module/utils/translator.rb'
require 'json'
require 'ostruct'

module CsvParser
  YEAR = ARGV[0] || "2025"
  INPUT_FOLDER  = "./src/#{YEAR}"
  OUTPUT_CSV_FOLDER = "./output/csv/#{YEAR}"
  OUTPUT_HTML_FOLDER = "./docs/#{YEAR}"

  class Runner
    def self.run
      new.run
    end

    def run
      process_files
    end

    private

    def process_files
      acro_files  = Dir.glob(File.join(INPUT_FOLDER, "*_acro.csv"))
      dance_files = Dir.glob(File.join(INPUT_FOLDER, "*_dance.csv"))

      acro_prefixes  = acro_files.map  { |f| File.basename(f, '_acro.csv') }
      dance_prefixes = dance_files.map { |f| File.basename(f, '_dance.csv') }

      validate_file_pairs(acro_prefixes, dance_prefixes)
      process_valid_pairs(acro_prefixes & dance_prefixes)
    end

    def validate_file_pairs(acro_prefixes, dance_prefixes)
      (acro_prefixes - dance_prefixes).each do |prefix|
        puts "❌ No matching _dance file found for prefix: #{prefix}"
      end
      (dance_prefixes - acro_prefixes).each do |prefix|
        puts "❌ No matching _acro file found for prefix: #{prefix}"
      end
      puts ""
    end

    def process_valid_pairs(valid_prefixes)
      valid_prefixes.each do |base_prefix|
        process_pair(base_prefix)
      end
    end

    def process_pair(base_prefix)
      acro_file  = File.join(INPUT_FOLDER, "#{base_prefix}_acro.csv")
      dance_file = File.join(INPUT_FOLDER, "#{base_prefix}_dance.csv")

      analysis_acro  = Parser.parse(acro_file,  Categories::ACRO,  false, false)
      analysis_dance = Parser.parse(dance_file, Categories::DANCE, false, false)

      generate_reports(base_prefix, analysis_acro, analysis_dance)
    end

    def generate_reports(base_prefix, analysis_acro, analysis_dance)
      content_csv = analysis_dance.csv_content + analysis_acro.csv_content
      generate_report_csv(base_prefix, content_csv)
      generate_summary_csv(base_prefix, analysis_acro, analysis_dance, content_csv)
      generate_summary_html(base_prefix, analysis_acro, analysis_dance, content_csv)
    end

    def generate_report_csv(base_prefix, content_csv)
      output_file = File.join(OUTPUT_CSV_FOLDER, "#{base_prefix}_report.csv")
      File.open(output_file, "w") do |f|
        f.write("anomaly,competition,category name,round,heat,couple,criteria,stdev,threshold,ratio,raw data\n")
        f.write(content_csv)
      end
      puts "✅ Created: #{output_file}"
    end

    def generate_summary_csv(base_prefix, analysis_acro, analysis_dance, content_csv)
      output_file = File.join(OUTPUT_CSV_FOLDER, "#{base_prefix}_summary.csv")
      File.open(output_file, "w") do |f|
        write_summary_header(f)
        write_anomalies_per_part(f, analysis_acro, analysis_dance)
        write_anomalies_per_criteria(f, analysis_acro, analysis_dance)
        write_anomalies_per_group(f, content_csv, analysis_acro, analysis_dance)
        write_top_anomalies(f, base_prefix, analysis_acro, analysis_dance)
      end
      puts "✅ Created: #{output_file}"
    end

    def generate_summary_html(base_prefix, analysis_acro, analysis_dance, content_csv)
      output_file = File.join(OUTPUT_HTML_FOLDER, "#{base_prefix}_summary.html")
      File.open(output_file, "w") do |f|
        f.write(generate_html_header(base_prefix))
        f.write(generate_html_body(base_prefix, analysis_acro, analysis_dance, content_csv))
        f.write(generate_html_footer)
      end
      puts "✅ Created: #{output_file}"
      puts ""
    end

    def generate_html_header(base_prefix)
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Analysis Summary - #{base_prefix}</title>
          <link rel="stylesheet" href="../assets/styles.css">
          <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
          <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
          <script src="https://cdnjs.cloudflare.com/ajax/libs/stacktable.js/1.0.3/stacktable.min.js"></script>
        </head>
        <body>
      HTML
    end

    def generate_html_body(base_prefix, analysis_acro, analysis_dance, content_csv)
      total_anomalies = analysis_acro.anomalies.count + analysis_dance.anomalies.count
      total_analyses = analysis_acro.number_of_analyses + analysis_dance.number_of_analyses
      total_percentage = calculate_percentage(OpenStruct.new(anomalies: OpenStruct.new(count: total_anomalies), number_of_analyses: total_analyses))

      <<~HTML
        <h1>Analysis Summary - #{base_prefix}</h1>
        
        <div class="section">
          <h2>Overview</h2>
          <div class="summary-grid" style="margin-bottom: 20px;">
            <div class="summary-card">
              <h3>Total Anomalies</h3>
              <div class="value" id="totalAnomalies">#{total_anomalies} / #{total_analyses}</div>
              <div class="progress-bar">
                <div class="progress-bar-fill" style="background-color: #{progress_bar_color(total_percentage)}; width: #{total_percentage}%;"></div>
              </div>
              <p>#{total_percentage}% anomalies</p>
            </div>
          </div>

          <div class="summary-grid" style="margin-top: 10px;">
            <div class="summary-card">
              <h3>Dancing Part Anomalies</h3>
              <div class="value" id="danceAnomalies">#{analysis_dance.anomalies.count} / #{analysis_dance.number_of_analyses}</div>
              <div class="progress-bar">
                <div class="progress-bar-fill" style="background-color: #{progress_bar_color(calculate_percentage(analysis_dance))}; width: #{calculate_percentage(analysis_dance)}%;"></div>
              </div>
              <p>#{calculate_percentage(analysis_dance)}% anomalies</p>
            </div>
            
            <div class="summary-card">
              <h3>Acrobatic Part Anomalies</h3>
              <div class="value" id="acroAnomalies">#{analysis_acro.anomalies.count} / #{analysis_acro.number_of_analyses}</div>
              <div class="progress-bar">
                <div class="progress-bar-fill" style="background-color: #{progress_bar_color(calculate_percentage(analysis_acro))}; width: #{calculate_percentage(analysis_acro)}%;"></div>
              </div>
              <p>#{calculate_percentage(analysis_acro)}% anomalies</p>
            </div>
          </div>
          
        </div>

        <div class="section">
          <h2>Anomalies per Criteria</h2>
          #{generate_criteria_table(analysis_acro, analysis_dance)}
        </div>

        <div class="section">
          <h2>Anomalies per Group</h2>
          #{generate_group_table(content_csv, analysis_acro, analysis_dance)}
        </div>

        #{generate_top_anomalies_section(base_prefix, analysis_acro, analysis_dance)}
      HTML
    end

    def progress_bar_color(percentage)
      if percentage < 10
        'green'
      elsif percentage < 20
        'orange'
      else
        'red'
      end
    end

    def generate_criteria_table(analysis_acro, analysis_dance)
      combined_analysis = Analyzer.analyze_per_criteria(
        analysis_dance.anomalies,
        analysis_dance.number_of_analyses / $criterias_couples_dance.count
      ) + Analyzer.analyze_per_criteria(
        analysis_acro.anomalies,
        analysis_acro.number_of_analyses
      )
      
      <<~HTML
        <table class="uniform-table">
          <colgroup>
            <col style="width: 25%;">
            <col style="width: 25%;">
            <col style="width: 25%;">
            <col style="width: 25%;">
          </colgroup>
          <thead>
            <tr>
              <th>Criteria</th>
              <th>Number of Anomalies</th>
              <th>Analyses Made</th>
              <th>Percentage</th>
            </tr>
          </thead>
          <tbody>
            #{combined_analysis.sort_by { |analysis| -analysis.percentage }.map do |analysis|
              translated_criteria = Translator.translate(analysis.criteria)
              color = if analysis.percentage < 10
                        'green'
                      elsif analysis.percentage < 20
                        'orange'
                      else
                        'red'
                      end
              <<~ROW
                <tr>
                  <td>#{translated_criteria}</td>
                  <td>#{analysis.counter}</td>
                  <td>#{analysis.number_of_analyses}</td>
                  <td>
                    <div class="progress-bar">
                      <div class="progress-bar-fill" style="background-color: #{color}; width: #{analysis.percentage}%;"></div>
                    </div>
                    #{analysis.percentage}%
                  </td>
                </tr>
              ROW
            end.join}
          </tbody>
        </table>
      HTML
    end

    def generate_group_table(content_csv, analysis_acro, analysis_dance)
      all_anomalies = analysis_acro.anomalies + analysis_dance.anomalies
      analysis_per_group = Analyzer.analyze_per_group(all_anomalies, content_csv)
      
      <<~HTML
        <table class="uniform-table">
          <colgroup>
            <col style="width: 25%;">
            <col style="width: 25%;">
            <col style="width: 25%;">
            <col style="width: 25%;">
          </colgroup>
          <thead>
            <tr>
              <th>Group</th>
              <th>Number of Anomalies</th>
              <th>Analyses Made</th>
              <th>Percentage</th>
            </tr>
          </thead>
          <tbody>
            #{analysis_per_group.sort_by { |analysis| -analysis.percentage }.map do |analysis|
              translated_criteria = Translator.translate(analysis.criteria)
              color = if analysis.percentage < 10
                        'green'
                      elsif analysis.percentage < 20
                        'orange'
                      else
                        'red'
                      end
              <<~ROW
                <tr>
                  <td>#{translated_criteria}</td>
                  <td>#{analysis.counter}</td>
                  <td>#{analysis.number_of_analyses}</td>
                  <td>
                    <div class="progress-bar">
                      <div class="progress-bar-fill" style="background-color: #{color}; width: #{analysis.percentage}%;"></div>
                    </div>
                    #{analysis.percentage}%
                  </td>
                </tr>
              ROW
            end.join}
          </tbody>
        </table>
      HTML
    end

    def generate_top_anomalies_section(base_prefix, analysis_acro, analysis_dance)
      return "" if base_prefix.downcase.include?("overall")
      
      all_anomalies = analysis_acro.anomalies + analysis_dance.anomalies
      top_anomalies = all_anomalies.sort_by { |anomaly| -anomaly.stdev_ratio }.first(5)
      
      <<~HTML
        <div class="section">
          <h2>Top 5 Anomalies</h2>
          <ul class="anomaly-list">
            #{top_anomalies.map do |anomaly|
              severity_class = case anomaly.stdev_ratio
                               when ->(r) { r > 2 }
                                 "high"
                               else
                                 "medium"
                               end
              <<~ANOMALY
                <li class="anomaly-item #{severity_class}">
                  #{anomaly.raw_entry.gsub("\n", "<br>")}
                </li>
              ANOMALY
            end.join}
          </ul>
        </div>
      HTML
    end

    def generate_html_footer
      <<~HTML
          <script src="../assets/scripts.js"></script>
          <script>
          $(document).ready(function() {
            $('.uniform-table').each(function() {
              $(this).stacktable({myClass:'stacked'});
            });
          });
        </script>
        </body>
        </html>
      HTML
    end

    def write_summary_header(f)
      f.write("Summary\n\n")
    end

    def write_anomalies_per_part(f, analysis_acro, analysis_dance)
      f.write("Number of anomalies per part,nb of anomalies, nb of analysis made,percentage of anomalies\n")
      f.write("Dancing part,#{analysis_dance.anomalies.count},#{analysis_dance.number_of_analyses},#{calculate_percentage(analysis_dance)}%\n")
      f.write("Acrobatic part,#{analysis_acro.anomalies.count},#{analysis_acro.number_of_analyses},#{calculate_percentage(analysis_acro)}%\n\n")
    end

    def write_anomalies_per_criteria(f, analysis_acro, analysis_dance)
      f.write("Number of anomalies per criteria,nb of anomalies, nb of analysis made,percentage of anomalies\n")
      combined_analysis = Analyzer.analyze_per_criteria(
        analysis_dance.anomalies,
        analysis_dance.number_of_analyses / $criterias_couples_dance.count
      ) + Analyzer.analyze_per_criteria(
        analysis_acro.anomalies,
        analysis_acro.number_of_analyses
      )
      
      combined_analysis.sort_by { |analysis| -analysis.percentage }.each do |analysis|
        translated_criteria = Translator.translate(analysis.criteria)
        f.write("#{translated_criteria},#{analysis.counter},#{analysis.number_of_analyses},#{analysis.percentage}%\n")
      end
      f.write("\n")
    end

    def write_anomalies_per_group(f, content_csv, analysis_acro, analysis_dance)
      f.write("Number of anomalies per group,nb of anomalies, nb of analysis made,percentage of anomalies\n")
      all_anomalies = analysis_acro.anomalies + analysis_dance.anomalies
      analysis_per_group = Analyzer.analyze_per_group(all_anomalies, content_csv)
      
      analysis_per_group.sort_by { |analysis| -analysis.percentage }.each do |analysis|
        translated_criteria = Translator.translate(analysis.criteria)
        f.write("#{translated_criteria},#{analysis.counter},#{analysis.number_of_analyses},#{analysis.percentage}%\n")
      end
      f.write("\n")
    end

    def write_top_anomalies(f, base_prefix, analysis_acro, analysis_dance)
      return if base_prefix.downcase.include?("overall")
      
      f.write("Top 5 anomalies\n")
      all_anomalies = analysis_acro.anomalies + analysis_dance.anomalies
      all_anomalies.sort_by { |anomaly| -anomaly.stdev_ratio }
                  .first(5)
                  .each { |anomaly| f.write(anomaly.raw_entry) }
      f.write("\n")
    end

    def calculate_percentage(analysis)
      (100 * (analysis.anomalies.count / analysis.number_of_analyses.to_f).round(2)).to_i
    end
  end
end

CsvParser::Runner.run