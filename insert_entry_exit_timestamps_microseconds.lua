

local function getCurrTimeStamp(bool_stringify)
    -- helper function to return the current epoch timestamp, in microseconds
    -- resolution.
    -- Parameter:
    --     bool_stringify:   a boolean on whether to return the current epoch
    --                       as a string (if True) or as a float (if False)

    local currTStamp = core.now()
    if bool_stringify then
        local s = string.format('%d%06d',
                                currTStamp["sec"], currTStamp["usec"])
        return s
    else
        local tstamp_int = currTStamp["sec"] * 1000000 + currTStamp["usec"]
        return tstamp_int
    end
end

local function getHeaderTagName(txn)
    -- helper function to return a canonical HTTP header tag (suffix) name.
    -- Returns a string with the canonical HTTP header tag (suffix) name to
    -- identify the transaction given "txn".

    local src_ip = txn.f:src()
    local src_port = txn.f:src_port()
    local dst_ip = txn.f:dst()
    local dst_port = txn.f:dst_port()

    -- local hostname = txn.f:env("HOSTNAME")

    local haproxy_frontend = txn.sf:fe_id()

    local header_tag = ( "-src-" .. src_ip .. "-" .. src_port ..
                         "-dst-" .. dst_ip .. "-" .. dst_port ..
                         -- "-at-" .. hostname ..
                         "-frontend-" .. haproxy_frontend )
    header_tag = header_tag:gsub("%.", "-")   -- replace all dots "."

    return header_tag
end

local function get_http_header_name(txn, bool_req_or_res_header)
    -- helper function to get the __full__, canonical header name associated
    -- to the transaction "txn". The boolean parameter
    -- "bool_req_or_res_header" is whether the header name should for a
    -- http-request header (if it is true), or for a http-response header (if
    -- it is false).
    -- Returns a string with the __full__, canonical header name associated
    -- to the transaction "txn" and that request-or-response http header.

    local header_suffix_id = getHeaderTagName(txn)
    local headerName

    if bool_req_or_res_header then
        headerName = "x-entry-timestamp" .. header_suffix_id
    else
       headerName = "x-return-timestamp" .. header_suffix_id
    end
    return headerName
end

function insert_timestamp_http_request_header(txn)
    -- Public LUA function called by HAProxy to add in HAProxy a custom HTTP
    -- request header with the current epoch timestamp, in microseconds
    -- resolution, with the time the incoming HTTP request has been received
    -- by HAProxy.
    --
    -- http://www.arpalert.org/src/haproxy-lua-api/1.7dev/index.html#HTTP.req_add_header

    local headerName = get_http_header_name(txn, true)

    local headerValue = getCurrTimeStamp(true)

    txn.http:req_add_header(headerName, headerValue)
end

local function calculate_and_insert_http_delay_header(txn, curr_tstamp,
                                                      rpt_threshold_microsecs)
    -- helper function called in response time to calculate the delay in
    -- microseconds between the request and response http headers, and then
    -- to insert a new http-response header with such delay. If the delay
    -- happens to be greater than a threshold, it also logs to syslog this
    -- slow connection as well as the delay it has incurred.
    --
    -- Receives as arguments the transaction "txn", the current timestamp in
    -- Unix epoch with microsecond resolution, and a third argument that is
    -- threshold at which to report a slow response to syslog, like a
    -- slow http requests log, a-la slow_query_log in MariaDB/MySQL.

    -- get the http-request header name we should have stamped this http
    -- connection when it came in:
    local headerName_entry_tstamp = get_http_header_name(txn, true):lower()

    local all_response_headers = txn.http:res_get_headers()

    -- see if this http-request header name came back from the backend server
    -- as a response header:
    if type(all_response_headers[headerName_entry_tstamp]) ~= nil then
        local entry_tstamp_header_value = all_response_headers[headerName_entry_tstamp]
        local entry_tstamp_value = tonumber(entry_tstamp_header_value[0])

        local backend_processing_delay = curr_tstamp - entry_tstamp_value

        local connTagId = getHeaderTagName(txn)
        local headerName = "x-delay" .. connTagId
        local headerValue = string.format('%d', backend_processing_delay)

        txn.http:res_add_header(headerName, headerValue)

        if backend_processing_delay > rpt_threshold_microsecs then
            local slow_url = (txn.f:path() or '') .. "?" .. (txn.f:query() or '')
            txn:Warning(string.format("Slow HTTP connection '%s' for url '%s': it has taken over %d microseconds: %d microseconds [entry at %d, return at %d]",
                                      connTagId, slow_url,
                                      rpt_threshold_microsecs,
                                      backend_processing_delay,
                                      entry_tstamp_value, curr_tstamp)
                       )
        end
    end
end

function insert_timestamp_http_response_header(txn)
    -- Public LUA function called by HAProxy to add in HAProxy a custom HTTP
    -- response header with the current epoch timestamp, in microseconds
    -- resolution, with the time the outgoing HTTP response has been received
    -- from the backend by HAProxy. It also adds as well a second HTTP response
    -- header with the delay in microseconds between the time the HTTP request
    -- headers were received from the client and the time the HTTP response
    -- headers were received from the backend.
    --
    -- http://www.arpalert.org/src/haproxy-lua-api/1.7dev/index.html#HTTP.res_add_header

    -- add first the HTTP response header with the time the response headers have
    -- been received from the backend.

    local headerName = get_http_header_name(txn, false)

    local curr_tstamp = getCurrTimeStamp(false)

    local headerValue = string.format('%d', curr_tstamp)

    txn.http:res_add_header(headerName, headerValue)

    -- add next the HTTP response header with the delay between the time
    -- the HTTP request headers were received from the client and the time the
    -- HTTP response headers were received from the backend.

    local slow_connection_threshold = 80000 -- 80000 microseconds
    -- See the chosing of threshold (100 milliseconds) at which to report here:
    -- http://www.aosabook.org/en/posa/high-performance-networking-in-chrome.html
    calculate_and_insert_http_delay_header(txn, curr_tstamp,
                                           slow_connection_threshold)

end

-- Register these LUA functions to be called by the http proxy server:

core.register_action("insert_timestamp_http_request_header", { "http-req" },
                     insert_timestamp_http_request_header)

core.register_action("insert_timestamp_http_response_header", { "http-res" },
                     insert_timestamp_http_response_header)
