module QuantikzServer

using Genie, Logging, LoggingExtras

function main()
  Base.eval(Main, :(const UserApp = QuantikzServer))

  Genie.genie(; context = @__MODULE__)

  Base.eval(Main, :(const Genie = QuantikzServer.Genie))
  Base.eval(Main, :(using Genie))
end

end
