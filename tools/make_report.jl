using GPUBenchmarks, Plots, Colors, BenchmarkTools, UnicodeFun

#########################
# Parameters

# lol we can't just use 0.0, because Plots.jl errors then
missing_val = 0.0 + eps(Float64)
text2pix = 1.0
ywidth = 2.5
window_size = (800, 500)


nice_colors = map([
    (0, 116, 217), # Blue
    (127, 219, 255), # Aqua
    (133,  20,  75), # Maroon
    (240,  18, 190), # Fuchsia
    (46, 204,  64), # Green
    (177,  13, 201), # Purple
    (57, 204, 204), # Teal
    (61, 153, 112), # Olive
    (255, 220,   0), # Yellow
    (255,  65,  54), # Red
    (1, 255, 112), # Lime
    (255, 133,  27), # Orange
    (0,  31,  63), # Navy
    (221, 221, 221), # Silver
    (17,  17,  17), # Black
    (170, 170, 170), # Gray
]) do x
    RGB(map(v-> v / 255, x)...)
end
nice_colors_hash = ["#a6cee3","#b2df8a","#33a02c","#fb9a99","#e31a1c","#fdbf6f","#ff7f00","#cab2d6","#6a3d9a","#1f78b4"]
nice_colors = parse.(Colorant, nice_colors_hash)


#######################
# helpers

function get_time(x::BenchmarkTools.Trial)
    time = minimum(x).time
    isinf(time) ? missing_val : time / 10^9
end

function judged_push!(benchset, benchmark, name)
    get_time(benchmark) == missing_val && return
    for benches in benchset
        judgment = judge(minimum(first(benches)[2]), minimum(benchmark))
        if judgment.time == :invariant
            push!(benches, (name, benchmark))
            return
        end
    end
    # we have a new unique benchresult and can open a new group
    push!(benchset, [(name, benchmark)])
    return
end
function get_log_n(N)
    # we should only use log10  or log2 for now!
    isinteger(log10(N)) && return string("10", to_superscript(Int(log10(N))))
    ispow2(N) && return string("2", to_superscript(Int(log2(N))))
    string(N)
end

function prettytime(t)
    if t < 1e3
        1, "ns"
    elseif t < 1e6
        1e3, "μs"
    elseif t < 1e9
        1e6, "ms"
    else
        1e9, "s"
    end
end
function smart_round(t)
    if t < 0.0001
        round(t, 9)
    elseif t < 0.1
        round(t, 4)
    else
        round(t, 1)
    end
end

get_trial(x::BenchmarkTools.Trial) = x
function get_trial(x)
    BenchmarkTools.Trial(
        BenchmarkTools.Parameters(),
        fill(Inf, 1000),
        fill(Inf, 1000),
        typemax(Int),
        typemax(Int)
    )
end

grouptime(x) = minimum(last(first(x))).time
function speedup!(benchset)
    sort!(benchset, by = grouptime)
    slowest = grouptime(benchset[end])
    map(x-> slowest / grouptime(x), benchset)
end

rect(w, h, x, y) = Shape(x + [0,w,w,0], y + [0,0,h,h])
function plot_speedup!(p, position, label, color)
    annotation = text(label, 9, RGB(0.2, 0.2, 0.2), :right, "helvetica")
    ps = annotation.font.pointsize
    w = (10 * ps) / text2pix
    shape = rect(-w, ps * ywidth, (position)...)
    plot!(p, shape, linewidth = 0, linecolor = RGBA(0,0,0,0), color = color, m = (color, stroke(0)))
    annotate!(p, [((position .+ (-4, 10text2pix))..., annotation)])
    position .- (w + (5 * text2pix), 0)
end

function plot_label!(p, position, label, color)
    shape = rect(10, 9 * ywidth, (position .- (12, 0))...)
    plot!(p, shape, linewidth = 0, color = color, linecolor = RGBA(1,1,1,0.2))
    position .- ((15text2pix), 0)
end

function plot_benchset(p, position, wstart, benchset, label_colors, speed_cmap)
    speedups = speedup!(benchset)
    abs_times = map(x-> minimum(x[1][2]).time, benchset)
    iterator = zip(reverse(speedups), speed_cmap, reverse(benchset), reverse(abs_times))
    for (speedup, scolor, benches, abs_time) in iterator
        position = plot_speedup!(p, position, prettytime(abs_time), scolor)
        position = plot_speedup!(p, position, @sprintf("%8.1fx", speedup), scolor)
        for (name, bench) in benches
            position = plot_label!(p, position, name, label_colors[name])
        end
        position = (wstart, position[2] + 11 * ywidth + 5)
    end
    position
end

function plot_samples(suite, baseline, devices, legend_colors)
    Nmax = maximum(unique(map(x-> x.N, suite)))
    sort_dev(dev) = minimum(first(filter(x-> x.device == dev && x.N == Nmax, suite)).benchmark).time
    devices = sort(devices, by = sort_dev)
    max_time = maximum(map(x-> minimum(x.benchmark).time, suite))
    divisor, unit = prettytime(max_time)
    str = IOBuffer()
    Ns = map(x-> x.N, baseline)
    Ns = [Ns[1], Ns[end]]
    print(str, "| device |")
    for n in Ns
        print(str, " N = ", get_log_n(n), " |")
    end
    print(str, "\n| --- | ")
    for i = 1:(length(Ns))
        print(str, " :---: |")
    end
    for device in devices
        c = legend_colors[device]
        colorhex = bytes2hex(reinterpret(UInt8, [c.r, c.g, c.b]))
        label = device_label(device)
        print(str, "\n| ", "![$label](https://placehold.it/15/$(colorhex)/000000?text=+) ", label, " | ")
        for n in Ns
            bench = filter(x-> x.N == n && x.device == device, suite)[1].benchmark
            basetime = minimum(filter(x-> x.N == n, baseline)[1].benchmark).time
            t = minimum(bench).time
            speedup = basetime / t
            print(str, " `", smart_round(t / divisor), " ", unit, "` `", smart_round(speedup), "x` |")
        end
    end
    String(take!(str))
end
function github_url(isimage, name...)
    str = joinpath(
        "https://github.com/JuliaGPU/GPUBenchmarks.jl/blob/master/",
        name...,
        isimage ? "?raw=true" : ""
    )
    # there is a better way to do this in HTTParser or so... keep forgetting where and how
    replace(str, " ", "%20")
end

##########################################
# plotting code

gr(size = window_size)


md_io = open(GPUBenchmarks.dir("results", string("results.md")), "w")

println(md_io, """
# GPU Benchmarks

Packages benchmarked:

[CuArrays](https://github.com/FluxML/CuArrays.jl) appears as: **cuarrays**

[GPUArrays](https://github.com/JuliaGPU/CLArrays.jl) appears as: **clarrays**

[ArrayFire](https://github.com/gaika/ArrayFire.jl) appears as: **arrayfire cl**, **arrayfire cu**


Julia Base Arrays appear as: **julia base**

Hardware used for GPU: **GTX 950**

Hardware used for Julia single and multithreaded backends: **Intel® Core™ i7-6700 CPU @ 3.40GHz × 4**

Julia's Array implementation is used as a baseline for performance and precision.
So the baseline is in most cases the maximum single threaded performance with SIMD acceleration.
The mean difference in the precision compared to the Julia baseline is plotted as points, with the size of difference corelating with point size.

---

""")


function device_label(device)
    # TODO rename devices in GPUArrays and GPUBenchmarks
    str = replace(string(device), "_", " ")
    if device == "opencl"
        "gpuarrays cl"
    elseif device == "cudanative"
        "gpuarrays cudanative"
    elseif device == "julia"
        "gpuarrays threaded"
    else
        str
    end
end
db = GPUBenchmarks.get_database()

most_current = filter(x-> x.timestamp == GPUBenchmarks.last_time_stamp(), GPUBenchmarks.get_database())

names = unique(GPUBenchmarks.device.(most_current))
prevts = sort(unique(GPUBenchmarks.timestamp.(db)))[1]

prevbs = filter(x-> x.timestamp == prevts, db)
namesprev = unique(GPUBenchmarks.device.(prevbs))
to_merge_names = namesprev[[1, 4, 6, 7]]
benchprev = filter(x-> x.device in to_merge_names, prevbs)
cu_pde = filter(x-> x.device == "cudanative" && x.name == "PDE", prevbs)

most_current = vcat(cu_pde, benchprev, most_current)
using GPUBenchmarks: codepath, name

most_current = map(most_current) do bench
    if bench.device == "cudanative"
        return BenchResult(bench, device = "cuarrays")
    else
        bench
    end
end

codepaths = unique(codepath.(most_current))

for elem in most_current
    t = get_time(elem.benchmark)
    if length(t) == 14
        println(elem)
    end
end

xx = filter(x-> x.device == "clarrays_gpu" && x.name == "Juliaset", most_current)
new_most_current = filter(x-> !(x.device == "clarrays_gpu" && x.name == "Juliaset"), most_current)


newxx = BenchResult[]
for N in ns
    push!(newxx, first(filter(x-> x.N == N, xx)))
end
most_current  = vcat(newxx, new_most_current)

for code_path in codepaths
    println(code_path)
    suites = unique(name.(filter(x-> codepath(x) == code_path, most_current)))
    mod = include(code_path)
    jl_name = basename(code_path)
    file_name, ext = splitext(jl_name)
    println(md_io, "### ", titlecase(file_name))
    println(md_io, mod.description)
    for suitename in suites
        suite = filter(x-> name(x) == suitename, most_current)
        println(md_io, "#### ", titlecase(suitename))
        i = 1
        legend_colors = Dict()
        main_plot = plot(
            xaxis = ("Problem size N", :log10), yaxis = "Speedup",
            legend = :topleft,
            background_color_legend = RGBA(1, 1, 1, 0.6),
            top_margin = 0,
            foreground_color_grid = RGB(0.6, 0.6, 0.6),
            axiscolor = RGB(0.2, 0.2, 0.2),
            markerstrokewidth = 0,
        );
        devices = unique(map(x-> x.device, suite))
        baseline = sort(filter(x-> x.device == "julia_base", suite), by = (x)-> x.N)
        base_times, Ns = map(x-> x.benchmark, baseline), map(x-> x.N, baseline)
        base_times = get_time.(base_times)
        for device in devices
            println(device, " ", suitename)
            device_benches = sort(filter(x-> x.device == device, suite), by = (x)-> x.N)
            if length(device_benches) == 14
                device_benches = device_benches[1:2:length(device_benches)]
            end
            times, Ns = map(x-> x.benchmark, device_benches), map(x-> x.N, device_benches)
            meandiff = map(x-> x.meandiffrence, device_benches) .* 3000.0

            println(">", length(times))
            times = base_times ./ get_time.(times)
            color = nice_colors[i]
            legend_colors[device] = color
            error_cmap = linspace(colorant"#E53A15", colorant"#AAE500", length(Ns))
            plot!(main_plot, Ns, times, line = (1, 0.4, color), m = (color, 5, stroke(0)), label = device_label(device))
            i += 1
        end
        legend_str = plot_samples(suite, baseline, devices, legend_colors)

        layout = @layout [
            a{0.5h}
            a{0.5w} a{0.5w}
        ]
        plot(main_plot, size = window_size ./ (1, 2))
        plotbase = GPUBenchmarks.dir("results", "plots")
        isdir(plotbase) || mkdir(plotbase)
        pngpath = joinpath(plotbase, suitename * ".png")
        println(pngpath)
        savefig(pngpath)
        println(pngpath)
        img_url = github_url(true, split(pngpath, Base.Filesystem.path_separator)[end-2:end]...)

        code_url = github_url(false, "benchmark", jl_name)
        println(md_io, "[![$suitename]($img_url)]($code_url)")
        println(md_io)
        println(md_io, legend_str)
        println(md_io)
        println(md_io, "[code]($code_url)")
        println(md_io)
        println(md_io, "___")
        println(md_io)
    end
end
close(md_io)
