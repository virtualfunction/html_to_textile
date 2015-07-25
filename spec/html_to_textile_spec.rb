require 'html_to_textile'
require 'yaml'

FIXTURES_PATH = File.expand_path '../fixtures', __FILE__

describe HtmlToTextile do
  content = YAML.load_file '%s/html_to_textile.yml' % FIXTURES_PATH 
  
  it 'converts' do
    Hash[*content].each do |html, expected_textile|
      HtmlToTextile.convert(html).should == expected_textile
    end
  end
end
