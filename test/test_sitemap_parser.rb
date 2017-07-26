require File.join(File.dirname(__FILE__), 'helper')

require 'typhoeus'

class TestSitemapParser < Test::Unit::TestCase
  def setup
    url = "https://example.com/sitemap.xml"
    local_file = File.join(File.dirname(__FILE__), 'fixtures', 'sitemap.xml')

    response = Typhoeus::Response.new(code: 200, body: File.read(local_file))
    Typhoeus.stub(url).and_return(response)

    @sitemap = SitemapParser.new url
    @local_sitemap = SitemapParser.new local_file

    @expected_count = 3
  end

  def test_array
    assert_equal Array, @sitemap.to_a.class
    assert_equal @expected_count, @sitemap.to_a.count
    assert_equal Array, @local_sitemap.to_a.class
    assert_equal @expected_count, @local_sitemap.to_a.count
  end

  def test_xml
    assert_equal Nokogiri::XML::NodeSet, @sitemap.urls.class
    assert_equal @expected_count, @sitemap.urls.count
    assert_equal Nokogiri::XML::NodeSet, @local_sitemap.urls.class
    assert_equal @expected_count, @local_sitemap.urls.count
  end

  def test_sitemap
    assert_equal Nokogiri::XML::Document, @sitemap.sitemap.class
    assert_equal Nokogiri::XML::Document, @local_sitemap.sitemap.class
  end

  def test_url_objects
    url1, url2, url3 = *@sitemap.to_a

    assert_equal "http://ben.balter.com/", url1.loc
    assert_equal DateTime.new(2014, 2, 8, 18, 45, 54, '-05:00'), url1.lastmod
    assert_equal "daily", url1.changefreq
    assert_equal 1.0, url1.priority

    assert_equal "http://ben.balter.com/about/", url2.loc
    assert_equal DateTime.new(2014, 2, 8, 18, 45, 54, '-05:00'), url2.lastmod
    assert_equal "weekly", url2.changefreq
    assert_equal 0.7, url2.priority

    assert_equal "http://ben.balter.com/contact/", url3.loc
    assert_equal "weekly", url3.changefreq
    assert_equal 0.7, url3.priority
  end

  def test_filter_to_a
    urls = @sitemap.to_a {|u| URI.parse(u.loc).path != "/"}
    assert_equal 2, urls.count
    assert_equal ["http://ben.balter.com/about/", "http://ben.balter.com/contact/"],
                 urls.map {|u| u.loc}
  end

  def test_404
    url = 'http://ben.balter.com/foo/bar/sitemap.xml'
    response = Typhoeus::Response.new(code: 404, body: "404")
    Typhoeus.stub(url).and_return(response)

    sitemap = SitemapParser.new url
    assert_raise RuntimeError.new("HTTP request to #{url} failed") do
      sitemap.urls
    end
  end

  def test_malformed_sitemap
    url = 'https://example.com/bad/sitemap.xml'
    malformed_sitemap = File.join(File.dirname(__FILE__), 'fixtures', 'malformed_sitemap.xml')
    response = Typhoeus::Response.new(code: 200, body: File.read(malformed_sitemap))
    Typhoeus.stub(url).and_return(response)

    sitemap = SitemapParser.new url
    assert_raise RuntimeError.new("No 'loc' element found") do
      sitemap.to_a.first.loc
    end
  end

  def test_malformed_sitemap_no_urlset
    url = 'https://example.com/bad/sitemap.xml'
    response = Typhoeus::Response.new(code: 200, body: '<foo>bar</foo>')
    Typhoeus.stub(url).and_return(response)

    sitemap = SitemapParser.new url
    assert_raise RuntimeError.new('Malformed sitemap, no urlset') do
      sitemap.to_a
    end
  end

  def test_nested_sitemap
    urls = ['https://example.com/sitemap_index.xml', 'https://example.com/sitemap.xml', 'https://example.com/sitemap2.xml']
    urls.each do |url|
      filename = url.gsub('https://example.com/', '')
      file = File.join(File.dirname(__FILE__), 'fixtures', filename)
      response = Typhoeus::Response.new(code: 200, body: File.read(file))
      Typhoeus.stub(url).and_return(response)
    end

    sitemap = SitemapParser.new 'https://example.com/sitemap_index.xml', :recurse => true
    assert_equal 6, sitemap.to_a.count
    assert_equal 6, sitemap.urls.count
  end

  def test_nested_sitemap_failure
    urls = ['https://example.com/sitemap_index.xml', 'https://example.com/sitemap.xml', 'https://example.com/sitemap2.xml']
    urls[0..1].each do |url|
      filename = url.gsub('https://example.com/', '')
      file = File.join(File.dirname(__FILE__), 'fixtures', filename)
      response = Typhoeus::Response.new(code: 200, body: File.read(file))
      Typhoeus.stub(url).and_return(response)
    end

    # make the third one fail
    failed_response = Typhoeus::Response.new(code: 400, body: "Kaboom")
    Typhoeus.stub(urls.last).and_return(failed_response)

    sitemap = SitemapParser.new 'https://example.com/sitemap_index.xml', :recurse => true
    assert_equal 3, sitemap.to_a.count
    assert_equal 3, sitemap.urls.count
    assert_not_nil sitemap.errors[urls.last]
  end
end
