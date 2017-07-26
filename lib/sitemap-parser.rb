require 'nokogiri'
require 'typhoeus'

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
            return response.body
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

  def to_a
    urls.map { |url| url.at("loc").content }
  rescue NoMethodError
    raise 'Malformed sitemap, url without loc'
  end
end
