
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

function calc_txn_delay_with_haproxy_vars(txn)
    -- Public LUA function called to obtain the string value of a http header
    -- with the delay in microseconds between two custom [HAProxy transaction]
    -- variables:
    --   variable: "txn.start_timestamp": has the Unix epoch in microsecond
    --             resolution of the time when the transaction was received
    --             from the client by HAProxy. (as a string)
    --   variable: "txn.exit_timestamp": has the Unix epoch in microsecond
    --             resolution of the time when the transaction was responded
    --             by the backend server to HAProxy. (as a string)
    --
    -- So the value returned by this function is:
    --         txn.exit_timestamp - txn.start_timestamp
    -- (In fact, the value returned is more detailed since it has both times:
    --         txn.exit_timestamp - txn.start_timestamp ..
    --         " from " .. txn.start_timestamp ..
    --         " till " .. txn.exit_timestamp
    -- )
    --
    -- Besides returning this value, if the delay happens to be greater than a
    -- threshold, it also logs to syslog this slow connection as well as the
    -- delay it has incurred. This allows the case of pure TCP proxying, where
    -- an http-header is not allowed.

    local start_tstamp = txn.get_var(txn, "txn.start_timestamp")
    -- we can omit the second one, getting the transaction variable
    -- "txn.exit_timestamp", and instead use core.now() with the current time.
    local exit_tstamp = txn.get_var(txn, "txn.exit_timestamp")

    if type(start_tstamp) ~= nil and type(exit_tstamp) ~= nil then

        local start_tstamp_num = tonumber(start_tstamp)
        local exit_tstamp_num = tonumber(exit_tstamp)
        local backend_delay_microseconds = exit_tstamp_num - start_tstamp_num

        if backend_delay_microseconds > 80000 then
            txn:Warning(string.format("Slow request: it has taken over %d microseconds: %d microseconds [entry at %s, return at %s]",
                                      80000, backend_delay_microseconds,
                                      start_tstamp, exit_tstamp_num)
                       )
        end

        return string.format('%d', backend_delay_microseconds) ..
               " from " .. start_tstamp .. " till " .. exit_tstamp
    else
        return "-1"
    end
end

-- Register these LUA functions to be called as [value] fetchers by the http proxy server:

core.register_fetches("tstamp_microsecs", function(txn)
    return getCurrTimeStamp(true)
end)

core.register_fetches("calc_txn_delay", calc_txn_delay_with_haproxy_vars)
