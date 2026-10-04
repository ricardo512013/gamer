--!strict
-- Minimal signal implementation used by server services and client controllers.

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
}

local Signal = {}

function Signal.new(): Signal
	local handlers: { (...any) -> () } = {}

	local signal: Signal = {
		Connect = function(_self: Signal, fn: (...any) -> ()): Connection
			table.insert(handlers, fn)
			local connection: Connection = {
				Disconnect = function(_conn: Connection)
					local index = table.find(handlers, fn)
					if index then
						table.remove(handlers, index)
					end
				end,
			}
			return connection
		end,
		Fire = function(_self: Signal, ...: any)
			for _, fn in table.clone(handlers) do
				task.spawn(fn, ...)
			end
		end,
	}
	return signal
end

return Signal
