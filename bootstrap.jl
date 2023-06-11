(pwd() != @__DIR__) && cd(@__DIR__) # allow starting app from bin/ dir

using QuantikzServer
const UserApp = QuantikzServer
QuantikzServer.main()
