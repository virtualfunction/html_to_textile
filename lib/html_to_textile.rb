# encoding: utf-8

require 'cgi'
require 'nokogiri'
require 'html_to_textile/version'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/starts_ends_with'

# = Convert HTML into textile. 
#
# This will discard any unrecognised tags, which is probably desired as most of 
# time you don't want junk mark up.
class HtmlToTextile

  NEWLINE = "\n"

  # SAX parser
  class Converter < Nokogiri::XML::SAX::Document
    # 
    # Tag translations
    # 

    # Maps tokens for opening and closing tags
    SHARED_TAGS = {
      # Text formatting
      :b      => '**',
      :strong => '*',
      :i      => '__',
      :em     => '_',
      :cite   => '??',
      :code   => '@',
      :span   => '%',
      # Special
      :img    => '!',
    }.freeze

    # Maps tokens for opening tags
    OPENING_TAGS = SHARED_TAGS.dup.update(
      # Headings
      :table => 'table. ',
      :h1 => 'h1. ',
      :h2 => 'h2. ',
      :h3 => 'h3. ',
      :h4 => 'h4. ',
      :h5 => 'h5. ',
      :h6 => 'h6. ',
      # Tables
      :th => '|_.',
      :td => '|',
      # Text formatting
      :del  => '[-',
      :ins  => '[+',
      :sup  => '[^',
      :sub  => '[~',
      # Special
      :a    => '"',
      :dt   => NEWLINE + '- ',
      :dd   => ' := ',
      # Structures
      :p    => 'p. ',
      :br   => NEWLINE,
      :pre  => 'pre. ',
      :blockquote => 'bq. ',
    ).freeze

    # Maps tokens for closing tags
    CLOSING_TAGS = SHARED_TAGS.dup.update(
      # Tables
      :tr   => '|',
      :td   => ' ',
      :th   => ' ',
      # Text formatting
      :del  => '-]',
      :ins  => '+]',
      :sup  => '^]',
      :sub  => '~]',
      # Special
      :a    => '":',
      :dl   => NEWLINE, # Not sure why I need this as it's a block element
    ).freeze
    
    # 
    # Simplified common entities (probably aren't tuched atm due to Nokogiri converting these)
    # 

    ENTITIES = [
      ['&#8220;', "'"   ], 
      ['&#8221;', "'"   ], 
      ['&#8212;', '--'  ], 
      ['&#8212;', '--'  ], 
      ['&#8211;', '-'   ], 
      ['&#8230;', '...' ], 
      ['&#215;',  ' x ' ], 
      ['&#8482;', '(TM)'], 
      ['&#174;',  '(R)' ], 
      ['&#169;',  '(C)' ], 
      ['&#8217;', "'"   ],
    ].freeze
    
    # 
    # Token look-up tables
    # 

    LIST = {
      :ol => '#',
      :ul => '*',
    }.freeze
    
    TABLE_SPANNING = {
      'colspan' => '/',
      'rowspan' => '\\',
    }.freeze
    
    TEXT_ALIGN = {
      'left'    => '<',
      'right'   => '>',
      'center'  => '=',
      'justify' => '<>',
    }.freeze

    VERTICAL_ALIGN = {
      'top'     => '^',
      'bottom'  => '~',
    }.freeze

    PADDING = {
      'left'    => '(',
      'right'   => ')',
    }.freeze

    # 
    # Tag classifications
    # 
    
    # Typical block elements
    BLOCK   = [ :code, :h1, :h2, :h3, :h4, :h5, :h6, :dl, :ol, :ul, :pre, :p, :div, :table ].freeze
    # This is kinda a special case for block elements
    ROW     = [ :tr, :li ].freeze
    # Note that th/td in Textile are sort of inline despite truly being block
    INLINE  = [ :b, :i, :strong, :em, :del, :ins, :sup, :sub, :cite, :span, :a, :blockquote, :th, :td, :img ].freeze

    attr_reader :converted, :original, :stack
    
    # TODO: Consider footnotes?
    # NOTE: Does not handle the edge case of definition lists

    def initialize
      @converted = ''
      @stack = []
    end

    # Opening tag callback
    def start_element(tag_name, attributes = [])
      # Preprocess, and push to stack
      element = tag_name.downcase.to_sym
      attribs = Hash[attributes]
      opening = OPENING_TAGS[element].to_s.dup
      styling = prepare_styles attribs, element
      spaces  = spacing element
      stack << [ element, attribs ]
      # Remove any bullets from parent LI tag
      if :li == element
        parent, = stack[-2]
        converted.gsub! /\*+\ $/, ''
        opening = LIST[parent] * count_element(:ul, :ol)
      end
      # Styling info gets positioned depending on element type
      content = case 
        when BLOCK.include?(element)
          opening.sub '.', styling + '.'
        when ROW.include?(element)
          (styling.empty?) ? opening + ' ' : opening + styling + ('.' if :td == element).to_s + ' '
        else opening + styling
      end
      # add white space & content
      append_white spaces
      converted << content
    end
    
    # Closing tag callback
    def end_element(tag_name)
      element, attribs = stack.pop
      spaces  = spacing element 
      closing = CLOSING_TAGS[element].to_s
      # Deal with cases for a/img
      converted << case element
        when :img
          attribs['src'].to_s + special_ending(attribs['alt']) + closing
        when :a
          special_ending(attribs['title']) + closing + attribs['href'].to_s
        else closing
      end
      append_white spaces
    end
    
    # Normal character stream
    def characters(text)
      changed = ENTITIES.inject(text) do |text, pair|
        text.gsub *pair
      end
      # Newlines should not be treated like <br /> tags, however don't indent 
      # on new lines so consume any preceeding whitespace
      content = CGI.unescapeHTML(changed).gsub(NEWLINE, ' ')
      content.rstrip! if content.ends_with? NEWLINE
      content.lstrip! if converted.ends_with? NEWLINE
      converted << content
    end

    # This will loose the CDATA, but it's rare this gets used in Textile
    def cdata_block(text)
      converted << text
    end
    
    private
    
    # Put white space at the end, but only if required
    def append_white(spacing)
      (-spacing.size).upto -1 do |i|
        space, last = spacing[i], converted[i]
        converted << space unless space == last or NEWLINE == last
      end
    end
    
    # Create styles, id, CSS classes, colspans, padding
    def prepare_styles(attribs, element)
      styling = attribs['class'].to_s.split /\s+/
      styling << '#' + attribs['id'] unless attribs['id'].blank?
      [].tap do |items|
        styles = attribs['style'].to_s.dup.strip
        unless styles.blank?
          if (BLOCK + ROW).include? element
            styles.gsub! /\s*padding-(left|right)\s*:\s*(\d+)em\s*\;?/i do |padding|
              items << PADDING[$1.downcase] * $2.to_i if padding.match /(PADDING.keys.join '|').*?(\d+)/i
              ''
            end
            styles.gsub! /\s*text-align\s*:\s*(\w+)\s*\;?/i do |align|
              items << TEXT_ALIGN[$1.downcase] if align.match /(#{ TEXT_ALIGN.keys.join '|' })/i
              ''
            end
            styles.gsub! /\s*vertical-align\s*:\s*(\w+)\s*\;?/i do |align|
              items << VERTICAL_ALIGN[$1.downcase] if align.match /(#{ VERTICAL_ALIGN.keys.join '|' })/i
              ''
            end
          end
          items << '{%s}' % styles unless styles.blank?
        end
        TABLE_SPANNING.each do |key, value|
          items << '%s%d' % [ value, attribs.delete(key) ] unless attribs[key].blank?
        end
        items << '(%s)' % styling.join(' ') unless styling.empty?
      end.join
    end
    
    # For special case closing tags (a and img)
    def special_ending(text)
      (text.present?) ? '(%s)' % text : ''
    end
    
    # Count number of items that match the given tag types
    def count_element(*types)
      stack.select { |level| types.include? level.first }.size
    end
    
    # Get spacing gap for a tag
    def spacing(element)
      return NEWLINE * 2 if BLOCK.include? element and count_element(:ul, :ol, :dl).zero?
      return NEWLINE if ROW.include? element
      ' '
    end
  end
  
  # Wrapper for SAX parser
  def self.convert(text)
    # Note, start-of-line is white space trimmed and we use HTML parsing to wrap up a fake HTML root node
    mark_up = text.gsub(/\n\ +/, NEWLINE).gsub(/\>\s*\n/, '> ')
    converter = Converter.new
    Nokogiri::HTML::SAX::Parser.new(converter).parse(mark_up)
    converter.converted.strip
  end
end
