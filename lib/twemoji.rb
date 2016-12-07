# frozen_string_literal: true

require "nokogiri"
require "json"
require "twemoji/version"
require "twemoji/map"
require "twemoji/configuration"

# Twemoji is a Ruby implementation, parses your text, replace emoji text
# with corresponding emoji image. Default emoji images are from Twiiter CDN.
module Twemoji
  # Find code by text, find text by code, and find text by unicode.
  #
  # @example Usage
  #   Twemoji.find_by(text: ":heart_eyes:") # => "1f60d"
  #   Twemoji.find_by(code: "1f60d")      # => ":heart_eyes:"
  #   Twemoji.find_by(unicode: "😍")        # => ":heart_eyes:"
  #   Twemoji.find_by(unicode: "\u{1f60d}") # => ":heart_eyes:"
  #
  # @option options [String] (optional) :text
  # @option options [String] (optional) :code
  # @option options [String] (optional) :unicode
  #
  # @return [String] Emoji text or code.
  def self.find_by(text: nil, code: nil, unicode: nil)
    if [ text, code, unicode ].compact!.size > 1
      fail ArgumentError, "Can only specify text, code or unicode one at a time"
    end

    case
    when text
      find_by_text text
    when unicode
      find_by_unicode unicode
    else
      find_by_code code
    end
  end

  # Find emoji code by emoji text.
  #
  # @example Usage
  #   Twemoji.find_by_text ":heart_eyes:"
  #   => "1f60d"
  #
  # @param text [String] Text to find emoji code.
  # @return [String] Emoji Code.
  def self.find_by_text(text)
    codes[must_str(text)]
  end

  # Find emoji text by emoji code.
  #
  # @example Usage
  #   Twemoji.find_by_code "1f60d"
  #   => ":heart_eyes:"
  #
  # @param code [String] Emoji code to find text.
  # @return [String] Emoji Text.
  def self.find_by_code(code)
    invert_codes[must_str(code)]
  end

  # Find emoji text by raw emoji unicode.
  #
  # @example Usage
  #   Twemoji.find_by_unicode "😍"
  #   => ":heart_eyes:"
  #
  # @param raw [String] Emoji raw unicode to find text.
  # @return [String] Emoji Text.
  def self.find_by_unicode(raw)
    invert_codes[unicode_to_str(raw)]
  end

  # Render raw emoji unicode from emoji text or emoji code.
  #
  # @example Usage
  #   Twemoji.render_unicode ":heart_eyes:"
  #   => "😍"
  #   Twemoji.render_unicode "1f60d"
  #   => "😍"
  #
  # @param text_or_code [String] Emoji text or code to render as unicode.
  # @return [String] Emoji UTF-8 Text.
  def self.render_unicode(text_or_code)
    text_or_code = find_by_text(text_or_code) if text_or_code[0] == ?:
    unicodes = text_or_code.split(?-)
    unicodes.map(&:hex).pack(?U*unicodes.size)
  end

  # Parse string, replace emoji text with image.
  # Parse DOM, replace emoji with image.
  #
  # @example Usage
  #   Twemoji.parse("I like chocolate :heart_eyes:!")
  #   => 'I like chocolate <img draggable="false" title=":heart_eyes:" alt="😍" src="https://twemoji.maxcdn.com/2/svg/1f60d.svg" class="emoji">!'
  #
  # @param text [String] Source text to parse.
  #
  # @option options [String] (optional) asset_root Asset root url to serve emoji.
  # @option options [String] (optional) file_ext   File extension.
  # @option options [String] (optional) class_name Emoji image's tag class attribute.
  # @option options [String] (optional) img_attrs  Emoji image's img tag attributes.
  #
  # @return [String] Original text with all occurrences of emoji text
  # replaced by emoji image according to given options.
  def self.parse(text, asset_root: Twemoji.configuration.asset_root,
                       file_ext:   Twemoji.configuration.file_ext,
                       class_name: Twemoji.configuration.class_name,
                       img_attrs:  Twemoji.configuration.img_attrs)

    options[:asset_root] = asset_root
    options[:file_ext]   = file_ext
    options[:img_attrs]  = { class: class_name }.merge! img_attrs

    if text.is_a?(Nokogiri::HTML::DocumentFragment)
      parse_document(text)
    else
      parse_html(text)
    end
  end

  # Parse string, replace emoji unicode value with image.
  # Parse DOM, replace emoji unicode value with image.
  #
  # @example Usage
  #   Twemoji.parse("I like chocolate 😍!")
  #   => 'I like chocolate <img draggable="false" title=":heart_eyes:" alt="😍" src="https://twemoji.maxcdn.com/2/svg/1f60d.svg" class="emoji">!'
  #
  # @param text [String] Source text to parse.
  #
  # @option options [String] (optional) asset_root Asset root url to serve emoji.
  # @option options [String] (optional) file_ext   File extension.
  # @option options [String] (optional) class_name Emoji image's tag class attribute.
  # @option options [String] (optional) img_attrs  Emoji image's img tag attributes.
  #
  # @return [String] Original text with all occurrences of emoji text
  # replaced by emoji image according to given options.
  def self.parse_unicode(text, asset_root: Twemoji.configuration.asset_root,
                       file_ext:   Twemoji.configuration.file_ext,
                       class_name: Twemoji.configuration.class_name,
                       img_attrs:  Twemoji.configuration.img_attrs)

    options[:asset_root] = asset_root
    options[:file_ext]   = file_ext
    options[:img_attrs]  = { class: class_name }.merge! img_attrs

    if text.is_a?(Nokogiri::HTML::DocumentFragment)
      parse_document(text, :filter_emojis_unicode)
    else
      parse_html(text, :filter_emojis_unicode)
    end
  end

  # Return all emoji patterns' regular expressions.
  #
  # @return [RegExp] A Regular expression consists of all emojis text.
  def self.emoji_pattern
    @emoji_pattern ||= /(#{codes.keys.map { |name| Regexp.quote(name) }.join("|") })/
  end

  def self.emoji_pattern_unicode
    @sorted_emoji_unicode_keys ||= invert_codes.keys.sort_by {|key| key.length }.reverse
    @emoji_pattern_unicode ||= /(#{@sorted_emoji_unicode_keys.map { |name| Regexp.quote(name.split('-').collect {|n| n.hex}.pack("U*")) }.join("|") })/
  end

  private

    # Ensure text is a string.
    #
    # @param text [String] Text to ensure to be a string.
    # @return [String] A String.
    # @private
    def self.must_str(text)
      text.respond_to?(:to_str) ? text.to_str : text.to_s
    end

    # Options hash for Twemoji.
    #
    # @return [Hash] Hash of options.
    # @private
    def self.options
      @options ||= {}
    end

    # Parse a HTML String, replace emoji text with corresponding emoji image.
    #
    # @param text [String] Text string to be parse.
    # @return [String] Text with emoji text replaced by emoji image.
    # @private
    def self.parse_html(text, filter= :filter_emojis)
      if filter == :filter_emojis && !text.include?(":")
        return text
      end

      self.send(filter, text)
    end

    # Parse a Nokogiri::HTML::DocumentFragment document, replace emoji text
    # with corresponding emoji image.
    #
    # @param doc [Nokogiri::HTML::DocumentFragment] Document to parse.
    # @return [Nokogiri::HTML::DocumentFragment] Parsed document.
    # @private
    def self.parse_document(doc, filter= :filter_emojis)
      doc.xpath(".//text() | text()").each do |node|
        content = node.to_html
        next if filter == :filter_emojis && !content.include?(":")
        next if has_ancestor?(node, %w(pre code tt))
        html = self.send(filter, content)
        next if html == content
        node.replace(html)
      end
      doc
    end

    # Find out if a node with given exclude tags has ancestors.
    #
    # @param node [Nokogiri::XML::Text] Text node to find ancestor.
    # @param tags [Array] Array of String represents tags.
    # @return [Boolean] If has ancestor returns true, otherwise falsy (nil).
    # @private
    def self.has_ancestor?(node, tags)
      while node = node.parent
        if tags.include?(node.name.downcase)
          break true
        end
      end
    end

    # Filter emoji text in content, replaced by corresponding emoji image.
    #
    # @param content [String] Contetn to filter emoji text to image.
    # @return [String] Returns a String just like content with all emoji text
    #                  replaced by the corresponding emoji image.
    # @private
    def self.filter_emojis(content, pattern=emoji_pattern)
      content.gsub(pattern) { |match| img_tag(match) }
    end

    def self.filter_emojis_unicode(content)
      self.filter_emojis(content, emoji_pattern_unicode)
    end

    # Returns emoji image tag by given name and options from `Twemoji.parse`.
    #
    # @param name [String] Emoji name to generate image tag.
    # @return [String] Emoji image tag generated by name and options.
    # @private
    def self.img_tag(name)
      # choose default attributes based on name or unicode value
      default_attrs = name.include?(":") ? default_attrs(name) : default_attrs_unicode(name)

      img_attrs_hash = default_attrs.merge! customized_attrs(name)

      %(<img #{hash_to_html_attrs(img_attrs_hash)}>)
    end

    PNG_IMAGE_SIZE = "72x72"
    private_constant :PNG_IMAGE_SIZE

    # Returns emoji url by given name and options from `Twemoji.parse`.
    #
    # @param name [String] Emoji name to generate image url.
    # @return [String] Emoji image tag generated by name and options.
    # @private
    def self.emoji_url(name, finder=:find_by_text)
      code = self.send(finder, name)

      if options[:file_ext] == "png"
        File.join(options[:asset_root], PNG_IMAGE_SIZE, "#{code}.png")
      elsif options[:file_ext] == "svg"
        File.join(options[:asset_root], "svg", "#{code}.svg")
      else
        fail "Unsupported file extension: #{options[:file_ext]}"
      end
    end

    # Returns user customized img attributes. If attribute value is any proc-like
    # object, will call it and the emoji name will be passed as argument.
    #
    # @param name [String] Emoji name.
    # @return Hash of customized attributes
    # @private
    def self.customized_attrs(name)
      custom_img_attributes = options[:img_attrs]

      # run value filters where given
      custom_img_attributes.each do |key, value|
        custom_img_attributes[key] = value.call(name) if value.respond_to?(:call)
      end
    end

    # Default img attributes: draggable, title, alt, src.
    #
    # @param name [String] Emoji name.
    # @return Hash of default attributes
    # @private
    def self.default_attrs(name)
      {
        draggable: "false".freeze,
        title:     name,
        alt:       render_unicode(name),
        src:       emoji_url(name)
      }
    end

    # Default img attributes: draggable, title, alt, src.
    #
    # @param unicode [String] Emoji unicode value.
    # @return Hash of default attributes
    # @private
    def self.default_attrs_unicode(unicode)
      {
        draggable: "false".freeze,
        title:     find_by_unicode(unicode),
        alt:       unicode,
        src:       emoji_url(unicode, :unicode_to_str)
      }
    end


    # Convert raw unicode to string key version
    # e.g. 🇲🇾 converts to "1f1f2-1f1fe"
    # @param unicode [String] Unicode value.
    # @return String representation of unicode value
    # @private
    def self.unicode_to_str(unicode)
      unicode.split("").map { |r| "%x" % r.ord }.join("-")
    end

    # Coverts hash of attributes into HTML attributes.
    #
    # @param hash [Hash] Hash of attributes.
    # @return [String] HTML attributes suitable for use in tag
    # @private
    def self.hash_to_html_attrs(hash)
      hash.map { |attr, value| %(#{attr}="#{value}") }.join(" ")
    end
end
