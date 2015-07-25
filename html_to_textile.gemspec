$:.push File.expand_path('../lib', __FILE__)

# Maintain your gem's version:
require 'html_to_textile/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |gem|
  gem.name        = 'html_to_textile'
  gem.version     = HtmlToTextile::VERSION
  gem.authors     = [ 'Jason Earl' ]
  gem.email       = [ 'jase@virtualfunction.net' ]
  gem.homepage    = 'https://github.com/virtualfunction/html_to_textile'
  gem.summary     = 'Convert simple HTML ino Textile'
  gem.description = 'Useful where you want to leverage a WYSIWYG editor, like CKeditor, but wouldrather use Textile behind the scenes as this helps prevent nasty MS office markup'

  gem.files = 
    Dir['{lib}/**/*'] + 
    [ 'README.rdoc' ]

  # gem.files = `git ls-files`.split "\n"
  gem.executables = gem.files.map do |file| 
    $1 if file =~ /^bin\/(.*)/
  end.compact

  gem.add_dependency 'nokogiri'
  gem.add_dependency 'activesupport'
  gem.add_development_dependency 'rspec'
end
