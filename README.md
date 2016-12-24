# measuring_delays_in_backends_using_Lua_in_HAProxy

Measure the time delay, in microseconds, of a http request passing through HAProxy version 1.7 till the backend http server starts the response, using Lua.

# WIP

This project is a *work in progress*. The implementation is *incomplete* and subject to change. The documentation can be inaccurate.

# Results

Once this LUA code is installed and used in HAProxy (and supported by the backend server), this code return HTTP-response headers like:

            x-entry-timestamp-src-127-0-0-1-55542-dst-127-0-0-1-8001-frontend-2: 1482553558298023
            x-return-timestamp-src-127-0-0-1-55542-dst-127-0-0-1-8001-frontend-2: 1482553558298317
            x-delay-src-127-0-0-1-55542-dst-127-0-0-1-8001-frontend-2: 294

In particular, note that the last HTTP-response header, the one starting with `x-delay-.*`, has the time delay in microseconds of the backend processing, as measured from HAProxy. (The first two HTTP-response headers shown in the example below, the ones starting with `x-entry-timestamp.*` and `x-return-timestamp.*`, return the epoch times in microseconds of entry in HAProxy and of return from HAProxy. It is optional to return these two headers to the client, but it is necessary to pass the `x-entry-timestamp.*` header to the backend server as a probe into the http-request headers, and it is necessary for the backend server to return as-is this http-request header `x-entry-timestamp.*` back in its http-response headers to HAProxy.) The suffixes above, e.g., `-src-127-0-0-1-55542-dst-127-0-0-1-8001-frontend-2`, are just tag IDs which uniquely identify the request (in this case, by specifying the TCP client and HAProxy front-end), and this avoids collision of HTTP headers where multiple servers happen to use the same header name, and allows to stack measures of the time-delay in different stages of the network, ie., when there are multiple haproxy's, each one measuring the time delay, pass the request to another measuring HAProxy upstream.

It is not necessary to return an `x-delay-.*` HTTP-response header to the client: the Lua code here has examples of how to log in HAProxy (e.g., to syslog) the slow backend requests it detects, so that the client sees no such HTTP-response headers.

# Set-up the Lua program in HAProxy

To make HAProxy load this Lua program `insert_entry_exit_timestamps_microseconds.lua`, you might use the following config instructions:

       global
              # ... HAProxy settings
              chroot /var/lib/haproxy
              
              # tune.lua.maxmem 1              # optional
              lua-load  /var/lib/haproxy/insert_entry_exit_timestamps_microseconds.lua
              
              # ... Other HAProxy settings

After loading this program, its functions are available to be used in other parts of HAProxy, like the functions `insert_timestamp_http_request_header` and `insert_timestamp_http_response_header`. A possible example of its use is seen in the Example section below.

# Example

If the backend http server happens to listen by port 8081 and is returning as-they-are in the http-response the http-request headers which match "x-entry-timestamp-.*" (to return this http-request header inserted by Lua in HAProxy is necessary), then a minimal HAProxy front-end which listens at port 8001 may be:

       # a minimal HAProxy http front-end which calculates the time delay
       # in microseconds resolution an http request takes.
            
       frontend my_lua_probed_frontend
              mode    http
              bind 0.0.0.0:8001
            
              http-request lua.insert_timestamp_http_request_header
              http-response lua.insert_timestamp_http_response_header
            
              default_backend  my_backend_which_echoes_x_entry_timestamp
            
            
       backend my_backend_which_echoes_x_entry_timestamp
              balance     roundrobin
            
              # different http servers in this backend which return
              # as-is the "x-entry-timestamp-.*" http-request headers they
              # find, e.g., for a simple test:
              server      static 127.0.0.1:8081 check


To follow with this example, although this remainder is not necessary for the HAProxy part, an example of a backend http-server which return as-is the "x-entry-timestamp-.*" http-request headers they find, is, using nginx and lua:

       # sample nginx backend which returns as-is all http-request headers which
       # match the pattern "x-entry-timestamp-.*" as http-response headers:
              
       server {
           listen 8081;
              
           client_header_buffer_size 2k;
              
           location ~ .* {
             default_type text/plain;
              
             content_by_lua '
                  local req_headers = ngx.req.get_headers(0)
                  local save_headers_preffix = string.lower("X-Entry-TimeStamp")
                  local len_save_headers_preffix = string.len(save_headers_preffix)
              
                  for k, v in pairs(req_headers) do
                      preffix_k = k:sub(1, len_save_headers_preffix):lower()
              
                      if preffix_k == save_headers_preffix then
                          ngx.header[k] = v
                      end
                  end
              
                  ngx.say("Test")
              
                  -- simulate a delay in the nginx http backend up to 200 milliseconds
              
                  -- local nginx_delay_milliseconds = math.random(200) / 1000.0
                  -- ngx.sleep(nginx_delay_milliseconds)
             ';
              
           }
       }

(To install nginx with Lua support, you might use the `nginx-extras` package in Debian/Ubuntu, or a bundle like OpenResty at [https://openresty.org/](https://openresty.org/) in RedHat/CentOS. You might as well compile nginx from its source code and enable the Lua module: [https://www.nginx.com/resources/wiki/modules/lua/](https://www.nginx.com/resources/wiki/modules/lua/).)

In Apache servers, to fulfill the requirement to return as-is the "x-entry-timestamp-.*" http-request headers you might use `Header echo` directive from the Apache `mod_headers` module, at [http://httpd.apache.org/docs/current/mod/mod_headers.html](http://httpd.apache.org/docs/current/mod/mod_headers.html).

