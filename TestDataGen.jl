using Distributions, Random

# globals
kCount = 25
cabins = 5
kPerCabin = convert(Int64,ceil(kCount/cabins))
dFileName = "data.csv"
argDict = Dict()

# main
function main(argDict)
    global kCount       = inarg("kCount",25)
    global cabins       = inarg("cabins",5)
    global chainLength  = inarg("chainLength",cabins)
    global avgChainLength = inarg("avgChainLength", 7)
    global dFileName    = inarg("outfile", "data.csv")
    global case         = inarg("case", "A")

    global kPerCabin    = convert(Int64,ceil(kCount/cabins))
    
    case = get(argDict,"case", "A")
    if (case == "A") 
        generateCaseAData(chainLength)
    elseif (case == "B")
        generateUnevenChainData(avgChainLength, chainLength)
    else 
        println("Case $case unimplemented")
    end
end


# This is generate chains from 1 to maxChainLength
# 1 is a loner
# 2 is a pair
function generateUnevenChainData(avg, max)
    println("Generating Case: B - Normal Chains")
    global kCount, cabins, kPerCabin, dFileName

    # Setup a normal Distributions
    d   = Normal(avg, 1.0)
    td  = truncated(d, 1, max)

    numChains = convert(Int64,ceil(kCount/chainLength))
    
    # open the file
    open(dFileName, "w") do io
        # Generate a set of student numbers
        local karr = sortperm(rand(kCount))
        ka = 0
        while ka < kCount
            chainLength = convert(Int64,ceil(rand(td)))
            if ka+chainLength > kCount
                chainLength = kCount - ka
            end
            kt = karr[ka+1:ka+chainLength]
            println(kt')
            dima = size(kt,1)
            if (dima==2) 
                write(io, "$(kt[i]),$(kt[i+1]),2\n")
                write(io, "$(kt[i+1]),$(kt[i]),2\n")
            else
                for i in 1:dima                                                                                                                               
                    write(io, "$(kt[i]),$(kt[1+i%dima]),2\n")                                                                                                      
                    write(io, "$(kt[i]),$(kt[1+ (i-2+dima)%dima]),2\n")
                end                                                                                            
            end    
            ka += chainLength
        end
    end # of open
end  # of generateUnevenChainData

# Happy Campers! this will generate perfect closed rings of cabin size
# last ring will be closed but may be smaller size
function generateCaseAData(chainLength)
    println("Generating Case: A - Happy Campers")
    global kCount, cabins, kPerCabin, dFileName

    numChains = convert(Int64,ceil(kCount/chainLength))
    
    # open the file
    open(dFileName, "w") do io
        # Generate a set of student numbers
        karr = reshape(sortperm(rand(numChains*chainLength)), numChains, chainLength)
        for ks in eachrow(karr)                                                                                                                               
            ks = filter(x->(x <= kCount), ks)                                                                                                             
            dima = size(ks,1)
            if (dima<=2) 
                println("Chain length must be equal to or greater than 3")
                exit()
            end                                                                                                                             
            for i in 1:dima                                                                                                                               
                write(io, string(ks[i]) * "," * string(ks[1+i%dima]) * ",2\n")                                                                                                      
                write(io, string(ks[i]) * "," * string(ks[1+ (i-2+dima)%dima]) * ",2\n")                                                                                            
            end                                                                                                                                           
            #println("-")                                                                                                                                  
        end
    end
    # 
    
    # randomize, create rings
    # output
end

function inarg(key, def)
    p = get(argDict,key,nothing)

    if (p===nothing) 
        return def
    elseif (typeof(def)!=typeof("String"))
        return parse(typeof(def),p)
    else 
        return p
    end
end


# The runner 
if abspath(PROGRAM_FILE) == @__FILE__
    # process arguments here
    println("Datagenertor for kids cabins problem.")
    global argDict = Dict()
    map(arg-> begin
                if !((m=match(r"(\S+)=(\S+)",arg)) === nothing)
                    argDict[m[1]] = m[2]
                else
                    argDict[arg] = true
                end
            end,ARGS )
    main(argDict)
else 
    # do this from repl 
    # include("datagen.jl")
    # setup some defaults for REPL testing
    global argDict = Dict()


    "Loaded."
end

