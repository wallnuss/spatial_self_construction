using MAT
using DataFrames
using Datetime

include("config.jl")
include("utils.jl")

jobs = Any[]
working_on = Dict{Int, RemoteRef}()
idle = Int[]

function runCluster(min, max, steps, fileName, outFolder = "results")
    try
        mkdir(outFolder)
    end

    dt = now()
    out = "$outFolder/$(year(dt))-$(month(dt))-$(day(dt))_$(hour(dt)):$(minute(dt)):$(second(dt))"
    mkdir(out)

    config = matread("data/$(fileName).mat")
    m1, m2 = max
    mi1, mi2 = min
    s1, s2 =steps
    vals = linspace2d(m1, mi1, s1, m2, mi2, s2)
    results = Any[]

    for v in vals
        push!(jobs, v)
    end

    # Setup everything
    nc, ng, c_ocl = determineWorkload()

    addprocs(nc + ng)
    idle = workers()
    require("job.jl")

    count = 1
    for id in workers()
        if count <= nc
            if c_ocl
                @at_proc id CPU_OCL = true
            else
                @at_proc id CPU_OCL = false
            end
            @at_proc id GPU_OCL = false
        else
            @at_proc id CPU_OCL = false
            @at_proc id GPU_OCL = true
        end
        count += 1
    end

    try
        running = true
        while running
            for (w, rref) in working_on
                if isready(rref)
                    rref = pop!(working_on, w) # remove from dict
                    result = fetch(rref) # fetch Remote Reference
                    push!(results, result) # store the result
                    push!(idle, w) # mark worker as idle
                end
            end

            while (length(idle) > 0) && (length(jobs) > 0)
                work_item = pop!(jobs) # get a work item
                w = pop!(idle) # get an idle worker
                rref = @spawnat w runProcess(config, work_item, out)
                working_on[w] = rref
            end

            if (length(jobs) == 0) && (length(working_on) == 0)
                running = false
            else
               yield()
               timedwait(anyready, 120.0, pollint=0.5)
            end
        end
    catch e
        println(e)
    finally
        df = resultsToDataFrame(results, out)
        show(df)
    end
end

function anyready()
    for rref in values(working_on)
        if isready(rref)
            return true
        end
    end
    return false
end

linspace2d(min1, max1, steps1, min2, max2, steps2) = [(x,y) for x in linspace(min1, max1, steps1), y in linspace(min2, max2, steps2)]

function resultsToDataFrame(results, folder)
    Param = Array(Any,0)
    T = Array(Float64,0)
    TS = Array(Float64,0)
    S = Array(Bool,0)
    MM = Array(Float64,0)
    MA = Array(Float64,0)
    SM = Array(Float64,0)
    SA = Array(Float64,0)
    SF = Array(Float64,0)
    SW = Array(Float64,0)
    SD = Array(Float64,0)
    FN = Array(Any,0)

    for (p, value) in results
        t, ts, s, mm, ma, sm, sa, sf, sw, sd, fn = value
        push!(Param, p)
        push!(T, t)
        push!(TS, ts)
        push!(S, s)
        push!(MM, mm)
        push!(MA, ma)
        push!(SM, sm)
        push!(SA, sa)
        push!(SF, sf)
        push!(SW, sw)
        push!(SD, sd)
        push!(FN, fn)
    end
    data = DataFrame(parameter=Param, time = T, timeToStable = TS, stable = S, meanM = MM, meanA = MA, structM = SM, structA = SA, structF = SF, structW = SW, structD = SD, fileName = FN)
    writetable("$folder/data.csv", data)
    return data
end


