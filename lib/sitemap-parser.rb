require 'nokogiri'
require 'time'
require 'typhoeus'
require 'zlib'

class SitemapParser

  def initialize(url, opts = {})
    @url = url
    @options = {:followlocation => true, :recurse => false}.merge(opts)
    @errors = Hash.new
  end

  def raw_sitemap
    @raw_sitemap ||= begin
      if @url =~ /\Ahttp/i
        request = Typhoeus::Request.new(@url, followlocation: @options[:followlocation])
        request.on_complete do |response|
          if response.success?
            content_type = response.headers_hash['Content-Type']
            content_encoding = response.headers_hash['Content-Encoding']

            case internal_content_type(content_type, content_encoding)
            when :gzip
              return Zlib::GzipReader.new(StringIO.new(response.body))
            when :xml
              return response.body
            else
              raise "Unexpected Content-Type: #{content_type}, Content-Encoding: #{content_encoding}"
            end
          else
            raise "HTTP request to #{@url} failed"
          end
        end
        request.run
      elsif File.exist?(@url) && @url =~ /[\\\/]sitemap\.xml\Z/i
        open(@url) { |f| f.read }
      end
    end
  end

  def sitemap
    @sitemap ||= Nokogiri::XML(raw_sitemap)
  end

  def urls
    @urls ||= begin
      if sitemap.at('urlset')
        sitemap.at("urlset").search("url")
      elsif sitemap.at('sitemapindex')
        found_urls = []
        if @options[:recurse]
          sitemap.at('sitemapindex').search('sitemap').each do |sitemap|
            child_sitemap_location = sitemap.at('loc').content
            begin
              found_urls << self.class.new(child_sitemap_location, :recurse => false).urls
            rescue => e
              @errors[child_sitemap_location] = e.message
            end
          end
        end
        found_urls.flatten
      else
        raise 'Malformed sitemap, no urlset'
      end
    end
  end

  def errors
    urls # force sitemap retrieval if it hasn't happened yet already
    @errors
  end

  def to_a(&block)
    result = urls.map { |e| URL.new(e) }
    result = result.select(&block) if block_given?
    result
  end

  private

  VALID_CONTENT_TYPES = [%r{text/xml}, %r{application/xml}, %r{text/plain}, %r{text/html}]

  def internal_content_type(type, encoding)
    types_match = VALID_CONTENT_TYPES.any? {|t| type =~ t}
    if type =~ /gzip/ ||
      (encoding =~ /gzip/ && types_match)
      :gzip
    elsif types_match
      :xml
    else
      :invalid
    end
  end

  # An object model representing the fields of a <url> element, cast to the
  # appropriate types
  class URL
    attr_accessor :loc, :lastmod, :changefreq, :priority

    # Construct a new instance with a Nokogiri XML element node
    def initialize(node)
      @node = node
    end

    def loc
      @loc ||= @node.at("loc").content
    rescue NoMethodError
      raise "No 'loc' element found"
    end

    def lastmod
      @lastmod ||= DateTime.parse(@node.at("lastmod").content)
    rescue NoMethodError
      raise "No 'lastmod' element found"
    end

    def changefreq
      @changefreq = @node.at("changefreq").content
    rescue NoMethodError
      raise "No 'changefreq' element found"
    end

    def priority
      @priority ||= @node.at("priority").content.to_f
    rescue NoMethodError
      raise "No 'priority' element found"
    end

    def inspect
      "<SitemapParser::URL loc=#{self.loc} lastmod=#{self.lastmod} changefreq=#{self.changefreq} priority=#{self.priority}>"
    end
  end
end
