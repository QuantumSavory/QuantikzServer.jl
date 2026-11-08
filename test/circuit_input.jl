using Base64, HTTP, Quantikz

const Q = Main.QuantikzServer

function circuit_response(input)
    # Match the browser form's application/x-www-form-urlencoded space encoding.
    query = replace(HTTP.escapeuri(input), "%20" => "+")
    request = HTTP.Request("GET", "/?circuit=" * query)
    response = Genie.Router.route_request(request, HTTP.Response())
    @test response.status == 200
    return String(response.body)
end

@testset "Literal circuit input" begin
    examples = [
        ("[CNOT(1,2), CPHASE(3,4), Measurement(1), Measurement(\"X\",2), Measurement(\"Z\",3,1)]",
         [CNOT(1,2), CPHASE(3,4), Measurement(1), Measurement("X",2), Measurement("Z",3,1)]),
        ("(H(1), P(2), Id(3), U(\"R_z(theta)/2\",4), SWAP(1,4))",
         [H(1), P(2), Id(3), U("R_z(theta)/2",4), SWAP(1,4)]),
        ("[Initialize(\"0\",[1,2]), MultiControl([1],[],[2],[]), MultiControlU(\"U\",[1],[],[2]), Noise([1,2]), NoiseAll()]",
         [Initialize("0",[1,2]), MultiControl([1],[],[2],[]), MultiControlU("U",[1],[],[2]), Noise([1,2]), NoiseAll()]),
        ("[Measurement(1,1), ClassicalDecision(\"X\",2,1), ParityMeasurement([\"X\",\"Z\"],[2,3])]",
         [Measurement(1,1), ClassicalDecision("X",2,1), ParityMeasurement(["X","Z"],[2,3])]),
    ]
    for (input, expected) in examples
        parsed = Q.parsecircuit(input)
        @test parsed isa Vector{Quantikz.QuantikzOp}
        @test circuit2string(parsed) == circuit2string(expected)
    end
    @test Q.parsecircuit("[H(39)]") isa Vector{Quantikz.QuantikzOp}
end

@testset "Reject executable and malformed input" begin
    mktempdir() do dir
        marker = joinpath(dir, "unexpected-side-effect")
        inputs = [
            "[touch($(repr(marker)))]",
            "[Base.touch($(repr(marker)))]",
            "[(touch($(repr(marker))); H)(1)]",
            "[H(touch($(repr(marker))))]",
            "[H(1); touch($(repr(marker)))]",
            raw"[U(\"$(1+1)\",1)]",
            "[H(1+1)]", "[H(1:2)]", "[H([1]...)]", "[H(target=1)]",
            "[getfield(Quantikz,:H)(1)]", "[Quantikz.H(1)]", "[H.(1)]",
            "[@time H(1)]", "[H(i) for i in 1:2]", "[H(true)]",
            "[H(0)]", "[H(-1)]", "[H(40)]", "[H(1.0)]", "[H('1')]",
            "[Noise([1,40])]", "[Noise([[1]])]", "[Noise([1,\"X\"])]",
            "[U(raw\"X\",1)]", "[U(\"X\",1; target=2)]", "[H()]",
            "", "1", "H", "nothing", "[]", "()", "[H(1)",
            repeat(" ", Q.MAX_LENGTH + 1),
        ]
        for input in inputs
            @test Q.parsecircuit(input) isa String
            @test !occursin("data:image/png", circuit_response(input))
            @test !ispath(marker)
        end
        @test Q.parsecircuit("[H(1)]\n[H(2)]") isa String
    end
end

@testset "Labels cannot introduce TeX or HTML" begin
    for label in [raw"\input{/etc/passwd}", "^^5cinput", "{X}", "%", "#", "&",
                  "\n", "X\n", "<script>alert(1)</script>"]
        @test Q.parsecircuit("[U($(repr(label)),1)]") isa String
        @test Q.parsecircuit("[ParityMeasurement([$(repr(label))],[1])]") isa String
    end
    # The syntax error includes the submitted text, so the error path must escape it.
    body = circuit_response("[U(\"<script>alert(1)</script>\",1),)]")
    @test !occursin("<script>alert(1)</script>", body)
    warning = first(split(body, "<form"))
    @test occursin("&lt;script&gt;alert(1)&lt;&#x2F;script&gt;", warning)
end

@testset "HTTP rendering and cache" begin
    mktempdir() do dir
        cd(dir) do
            empty!(Q.filecache)
            input = "[H(1), CNOT(1,2), Measurement(2)]"
            body = circuit_response(input)
            image = match(r"data:image/png;base64,([^\"]+)", body)
            @test image !== nothing
            if image !== nothing
                @test base64decode(image[1])[1:8] == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
            end
            @test occursin("TeX code for this image", body)
            @test occursin("&amp;", body)
            @test circuit_response(input) == body
            @test length(Q.filecache) == 1
            empty!(Q.filecache)
        end
    end
end
