# measuring_delays_in_backends_using_Lua_in_HAProxy

Measure the time delay, in microseconds, of a http request passing through HAProxy version 1.7 till the backend http server starts the response, using Lua.

# WIP

This project is a *work in progress*. The implementation is *incomplete* and subject to change. The documentation can be inaccurate.

# Results

Once this LUA code is installed and used in HAProxy (and supported by the backend server), this code return HTTP-response headers like:

            x-entry-timestamp-src-127-0-0-1-55542-dst-127-0-0-1-8001-frontend-2: 1482553558298023
            x-return-timestamp-src-127-0-0-1-55542-dst-127-0-0-1-8001-frontend-2: 1482553558298317
            x-delay-src-127-0-0-1-55542-dst-127-0-0-1-8001-frontend-2: 294

In particular, note that the last HTTP-response header, the one starting with `x-delay-.*`, has the time delay in microseconds of the backend processing, as measured from HAProxy. (The first two HTTP-response headers shown in the example below, the ones starting with `x-entry-timestamp.*` and `x-return-timestamp.*`, return the epoch times in microseconds of entry in HAProxy and of return from HAProxy. It is optional to return these two headers to the client, but it is necessary to pass the `x-entry-timestamp.*` header to the backend server as a probe into the http-request headers, and it is necessary for the backend server to return as-is this http-request header `x-entry-timestamp.*` back in its http-response headers to HAProxy.) The suffixes above, e.g., `-src-127-0-0-1-55542-dst-127-0-0-1-8001-frontend-2`, are just tag IDs which uniquely identify the request (in this case, by specifying the TCP client and HAProxy front-end), and this avoids collision of HTTP headers where multiple servers happen to use the same header name, and allows to stack measures of the time-delay in different stages of the network, ie., when there are multiple haproxy's, each one measuring the time delay, and pass the request to another measuring HAProxy upstream, so a collision in a header name can happen.

It is not necessary to return an `x-delay-.*` HTTP-response header to the client: the Lua code here has examples of how to log in HAProxy (e.g., to syslog) the slow backend requests it detects, so that the client sees no such HTTP-response headers.

# Set-up the Lua program in HAProxy

To make HAProxy load this Lua program `insert_entry_exit_timestamps_microseconds.lua`, you might use the following config instructions:

       global
              # ... HAProxy settings
              chroot /var/lib/haproxy
              
              # tune.lua.maxmem 1              # optional
              lua-load  /var/lib/haproxy/insert_entry_exit_timestamps_microseconds.lua
              
              # ... Other HAProxy settings

After loading this program, its functions are available to be used in other parts of HAProxy, like the functions `insert_timestamp_http_request_header` and `insert_timestamp_http_response_header`. A possible example of its use is seen in the [Example](#Example) section below.

# Example

If the backend http server happens to listen by port 8081 and is returning as-they-are in the http-response the http-request headers which match `x-entry-timestamp-.*` (to return this http-request header inserted by Lua in HAProxy is necessary), then a minimal HAProxy front-end which listens at port 8001 may be:

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


To follow with this example, although this remainder is not necessary for the HAProxy part, an example of a backend http-server which return as-is the `x-entry-timestamp-.*` http-request headers they find, is, using nginx and lua:

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

In Apache servers, to fulfill the requirement to return as-is the `x-entry-timestamp-.*` http-request headers, you might use `Header echo` directive from the Apache `mod_headers` module, at [http://httpd.apache.org/docs/current/mod/mod_headers.html](http://httpd.apache.org/docs/current/mod/mod_headers.html).


# Another way

A different way to measure the time delay spent by the backend is to use variables in HAProxy, `set-var(my_variable_name)`, instead of the way described above of adding an HTTP-request header `x-entry-timestamp-.*` to the request upstream, and then the backend echoing it back in HTTP-response headers.

With `set-var(my_variable_name)`, HAProxy creates a new (transaction) variable that then the LUA code called by HAProxy uses. To obtain the value of the current epoch of time in microsecond resolution, you need to program an HAProxy `fetcher`. There is possible code to do so in [flexible_for_TCP_experimental/using_vars_for_case_of_TCP_proxying.lua](flexible_for_TCP_experimental/using_vars_for_case_of_TCP_proxying.lua) in this repository. A minimalistic example of using it might be:

       global
              # ... HAProxy settings
              chroot /var/lib/haproxy
               
              lua-load  /var/lib/haproxy/using_vars_for_case_of_TCP_proxying.lua
               
              # ... Other HAProxy settings

       frontend my_frontend
               mode    tcp
               # option tcplog       # probably
                
               bind 0.0.0.0:8002
                
               # maxconn 65536        # very probably, to guard yourself against possible DoS,
                                      # for some value of "maxconn", not necessarily 65536,
                                      # according to your RAM.
                
               default_backend  my_backend


       backend my_backend
               balance     roundrobin
                
               # define the HAProxy custom transaction variables (that are prefixed by
               # "txn.") which obtain their value from custom HAProxy fetchers in Lua:
                
               tcp-request content set-var(txn.start_timestamp) lua.tstamp_microsecs()
                
               tcp-response content set-var(txn.exit_timestamp)  lua.tstamp_microsecs()
                
               tcp-response content set-var(txn.delay_microseconds)  lua.calc_txn_delay()
               http-response  add-header "x-delay-microseconds-haproxy"   %[var(txn.delay_microseconds)]
                
               tcp-response content unset-var(txn.start_timestamp)
               tcp-response content unset-var(txn.exit_timestamp)
               tcp-response content unset-var(txn.delay_microseconds)
                
               server      static 127.0.0.1:8081 check

If implemented, this example above will answer by inserting a HTTP-response header like:

               x-delay-microseconds-haproxy: 99 from 1482594022876865 till 1482594022876964

where the delay of the backend processing was 99 microseconds, and the other times reported in the HTTP header are the epoch in microseconds of when the request was received and when it was responded.

HAProxy gives a several flexible ways to use Lua embedding (actions, fetchers, services, tasks, etc), and there are differences between the approach of inserting HTTP-request headers and using transaction variables proposed in this repository. The first is that, in the former, the backend upstream needs to echo back the HTTP-request header `x-entry-timestamp-.*` it receives, so the backend needs to collaborate with HAProxy, while in the latter the variables are all handled by HAProxy and the embedded Lua code, so nothing is required in the backend server upstream.

The second difference is that the former approach only works for HTTP proxies since it inserts a new HTTP-request header as a probe, while the latter does not need to change the request so it can be extended also to TCP-proxies (in the case of non-HTTP TCP proxies, you can not use the setting above:

               http-response  add-header "x-delay-microseconds-haproxy"   %[var(txn.delay_microseconds)]

so what you need to use is that `lua.calc_txn_delay()` has side-effects and it logs, or reports, the duration of the backend request, e.g., like for slow requests. The Lua code provided shows examples of this.)

The third difference between both approaches is that in the former you do not need a `maxconn 65536` (or some value) in the frontend, while in the latter it might be necessary to avoid DoS.

