#!/usr/bin/ruby
#
# PageScan
#    by d3t0n4t0r
#
# version: 0.1
# 
# changelog:
# 	21 Oct 2012 - Project started 
# 	08 Nov 2012 - (0.1) Initial release
#
# WTFPL - Do What The Fuck You Want To Public License
# ---------------------------------------------------
# This program is free software. It comes without any warranty, to
# the extent permitted by applicable law. You can redistribute it
# and/or modify it under the terms of the Do What The Fuck You Want
# To Public License, Version 2, as published by Sam Hocevar. See
# http://sam.zoy.org/wtfpl/COPYING for more details.


require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'uri'
require 'net/http'

$useragent = {
	"User-Agent" => "Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; Win64; x64; Trident/4.0; .NET CLR 2.0.50727; SLCC2; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; MDDC; Tablet PC 2.0)", 
	"Referer" => "http://www.google.com/"
}
$seq = []

class Geturl
	attr_reader :url, :ip, :blist, :code, :urlredirect, :con, :js, :iframe, :link


	def initialize(url)
		@url = httpurl(url)
		$seq << @url
		@ip = get_ip(@url)
		@blist = get_blacklisted(@url)
		@code = ''
		@urlredirect = ''
		@con = ''
		@js = []
		@iframe = []
		@link = []
		
		go
	end

	def go
		response = get_content(@url)
		
		if response.instance_of?(SocketError) and response.to_s =~ /getaddrinfo:\sName\sor\sservice\snot\sknown/
			@code = "[ERROR] Unable to resolve host address"
		elsif response.instance_of?(Errno::ECONNREFUSED) and response.to_s =~ /Connection\srefused\s-\sconnect\(2\)/
			@code = "[ERROR] Connection refused"
		else
			parsecon = Nokogiri::HTML(response.body)
			@code = response.code
			redirect(response)	
			@con = response.body
			@js = parse_js(parsecon)
			@iframe = parse_iframe(parsecon)
			@link = parse_link(parsecon)
		end
	end

	def httpurl(url)
        	if (url =~ URI::regexp(%w(http https))).nil?
                	url = "http://" + url
        	end

        	url = URI.escape(url)

        	return url
	end

	def get_ip(url)
        	hostname = URI.parse(url).host
        	ip = `dig +short @8.8.8.8 #{hostname}` # CHEATER !!
		
		if ip.empty? or ip.nil?
			ip = hostname if hostname.match(/(?:\d{1,3}\.){3}\d{1,3}/)
		else
			ip = ip.scan(/((?:\d{1,3}\.){3}\d{1,3})/).flatten
		end

        	return ip
	end

	def get_content(uri)
                begin
                        response = ''
                        uri = URI.parse(uri)
                        http = Net::HTTP.new(uri.host, uri.port)
                        request = Net::HTTP::Get.new(uri.request_uri)
                        request.initialize_http_header($useragent)
			
                        response = http.request(request)
			
			if response.code.match(/404/)
				return ""
			else
                        	return response
			end
                rescue => e
                        return e
                end
        end

	def redirect(response)
		# try to figure out how to combine 'refresh' with 'Refresh'
		# document.location='http://blabla.com'
		# window.location="Shipping_Label_USPS.zip";
		# window.location.href="login.jsp?backurl="+window.location.href;
		# window.navigate("top.jsp");
		# self.location="top.htm"
		# top.location.href
		# top.location="error.jsp";
		#

		if @code =~ /302/ or @code =~ /301/
			if response['Location'] =~ /http|https/
				@urlredirect = response['Location']
				$seq << @urlredirect
			else
				@urlredirect = @url + response['Location']
				$seq << @urlredirect
			end
		else
			unless response.body.empty? or response.body.nil?
                		html = ''
                		url_redirect = []
                		meta_redirect = ''

                		html = Nokogiri::HTML(response.body)

                		jscode = parse_js(html)
                		jscode.each do |js|
                        		if js[1].match(/location.replace\(\".*?\"\);/)
                                		url_redirect <<  js[1].scan(/location.replace\(\"(.*?)\"\);/)
                        		end
                		end

                		html.search("meta[http-equiv='refresh']").map do |meta|
                        		if meta['content'].match(/url=/)
                                		url_redirect << meta['content'].scan(/url=(.*?)$/)
                        		end
                		end

                		html.search("meta[http-equiv='Refresh']").map do |meta|
                        		if meta['content'].match(/url=/)
                                		url_redirect << meta['content'].scan(/url=(.*?)$/)
                        		end
                		end

				url_redirect.flatten!
				url_redirect.uniq!

                		unless url_redirect.empty? or url_redirect.nil?
                                	if url_redirect.length == 1
						@urlredirect = url_redirect.to_s
						$seq << @urlredirect
                                	else
						@urlredirect = url_redirect[0].to_s
						$seq << @urlredirect
                        		end
				end
                	end
        	end
	end

	def parse_js(parsecon)
		tempsrc = ''
        	tempcode = ''
        	js = []

        	unless parsecon.nil?
                	parsecon.search('script').map do |scr|
                        	tempsrc = ''
                        	tempcode = ''

                        	unless scr['src'].nil?
                                	tempsrc = URI.escape(URI.parse(@url).merge(URI.parse(scr['src'])).to_s)
                                	begin
                                        	tempcode = get_content(tempsrc).body
                                	rescue
                                	end
                        	end

                        	unless scr.text.empty?
                                	tempcode = scr.text
                        	end

                        	js << [tempsrc,tempcode]
                	end
        	end

        	return js
	end

	def parse_iframe(parsecon)
		# Check Iframe on JavaScript code in print()  
		# document.write('<iframe src="http://blabla.com" scrolling="auto" frameborder="no" align="center" height="2" width="2"></iframe>');
        	# Check <IFRAME></IFRAME>
        	# <frame src="http://lopas-morka-kestas.eu.pn/forums.ws15,16,650,91478678/" name="dot_tk_frame_content" scrolling="auto" noresize>
        	# Get iframe content
        	# Whitelist:
        	# - facebook
        	# -  http://platform.twitter.com/widgets/follow_button.html?screen_name=bnp2tki

		iframe = []

        	unless parsecon.nil?
                	parsecon.search('iframe').map do |ifr|
                        	iframe << URI.parse(@url).merge(URI.parse(ifr['src'])).to_s
                	end
        	end

        	return iframe.uniq
	end

	def parse_link(parsecon)
        	links = []

        	unless parsecon.nil?
                	parsecon.search('a').map do |lin|
                        	begin
                                	links << URI.escape(URI.parse(@url).merge(URI.parse(lin['href'])).to_s)
                        	rescue
                        	end
                	end
        	end

        	return links.uniq
	end

	def get_blacklisted(site)
		result = Hash.new
        	result.merge!(google(site))
        	result.merge!(norton(site))
		result.merge!(mcafee(site))

		return result
	end

	def google(site)
        	gurl = "http://safebrowsing.clients.google.com/safebrowsing/diagnostic?site="
        	blacklist = 'No'

        	gcon = get_content(gurl+site)


        	unless gcon.nil?
                	if gcon.body.match(/Site\s{1}is\s{1}listed\s{1}as\s{1}suspicious/i)
                        	blacklist = 'Yes'
                	end
        	end

        	return :google => blacklist
	end

	def norton(site)
		# PROBLEM: CAPTCHA PAGE
		# "http://safeweb.norton.com/rate_limit?parameters=%2Freport%2Fshow%3Furl%3Dhttp%3A%2F%2Fimg.airparkfashionswitch.com%2Flinks%2Fdemands-lower.php
        	nurl = "http://safeweb.norton.com/report/show?url="
        	blacklist = 'No'

        	ncon = get_content(nurl+site)

        	unless ncon.nil?
                	if ncon.body.match(/<div\s{1,}class="ratingIcon\s{1,}icoWarning">.*?<label>\s{0,}WARNING/m)
                        	blacklist = 'Warning'
                	elsif ncon.body.match(/<div\s{1,}class="ratingIcon\s{1,}icoCaution">.*?<label>\s{0,}CAUTION/m)
                        	blacklist = 'Caution'
                	elsif ncon.body.match(/<div\s{1,}class="ratingIcon\s{1,}icoUntested">.*?<label>\s{0,}UNTESTED/m)
                        	blacklist = 'Untested'
                	end
        	end

        	return :norton => blacklist
	end

	def mcafee(site)
		murl = "http://www.siteadvisor.com/sites/"
		blacklist = "No"
		
		mcon = get_content(murl+site)

		unless mcon.nil?
		end
		
		return :mcafee => blacklist
	end
end
