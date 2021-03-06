using LinearAlgebra
using Parameters
using IterativeSolvers
using Plots
using BenchmarkTools
using FastGaussQuadrature
using BenchmarkTools
using ForwardDiff
using QuantEcon
using GLM
################################### Model types #########################

struct ModelParametersEnd{R <: Real}
    β::R
    d::R
    B_::R
    γ::R
    σ::R
    α::R
    ζ::R
    homeY::R
end

struct ModelFiniteElementEnd{R <: Real,I <: Integer}
    elements::Array{R,2}
    elementsID::Array{I,2}
    kGrid::Array{R,1}
    KGrid::Array{R,1}
    m::I
    wx::Array{R,1}
    ax::Array{R,1}
    nk::I
    nK::I
    ne::I
end

struct ModelMarkovChainEnd{R <: Real,I <: Integer}
    states::Array{R,2}
    statesID::Array{I,2}
    aggstatesID::Array{I,1}
    ns::I
    nis::I
    nas::I
    πz::Array{R,2} #aggregate transition
    Π::Array{R,2}
    IndStates::Array{R,1}
    AggStates::Array{R,1}
end

struct ModelDistributionEnd{R <: Real,I <: Integer}
    DistributionSize::I
    DistributionAssetGrid::Array{R,1}
    InitialDistribution::Array{R,2}
    AggShocks::Array{I,1}
    TimePeriods::I
end


struct KSMarkovFiniteElementEnd{R <: Real,I <: Integer}
    Guess::Array{R,1}
    GuessM::Array{R,3}
    LoMK::Array{R,1}
    LoML::Array{R,1}
    Parameters::ModelParametersEnd{R}
    FiniteElement::ModelFiniteElementEnd{R,I}
    MarkovChain::ModelMarkovChainEnd{R,I}
    Distribution::ModelDistributionEnd{R,I}
end


#Include ayiagari functions and types
#include("ks.jl")

"""
Construct and Ayiagari model instace of all parts needed to solve the model
"""
function KSModelEnd(
    UnempDurG::R = 1.5,
    UnempDurB::R = 2.5,
    Corr::R = 0.25,
    UnempG::R = 0.04,
    UnempB::R = 0.1,
    DurZG::R = 8.0,
    DurZB::R = 8.0,
    nk::I = 50, #asset grid size
    kMax::R = 200.0, #uppper bound on capital
    nK::I = 4, #aggregate capital grid size
    KMax::R = 12.0, #upper bound on aggregate capital
    KMin::R = 10.5,
    gZ::R = 1.01,
    bZ::R = 0.99,
    empS::R = 1.0,
    unempS::R = 0.0,
    β::R = 0.99,
    d::R = 0.025,
    B_::R = 0.0,
    γ::R = 1.0/2.9,
    σ::R = 1.0,
    α::R = 0.36,
    ζ::R = 10000000000.0,
    homeY::R = 0.07,
    Kg1::R =0.1,
    Kg2::R =0.96,
    Kb1::R =0.1,
    Kb2::R =0.96,
    Lg1::R =-0.5,
    Lg2::R =-0.25,
    Lb1::R =-0.6,
    Lb2::R =-0.25,
    NumberOfHouseholds::I = 700,
    TimePeriods::I = 8000,
    DistributionUL::R = 200.0,
    NumberOfQuadratureNodesPerElement::I = 2
) where{R <: Real,I <: Integer}


    ###################################################
    ################   Stochastic process #############
    ###################################################
    # unemployment rates depend only on the aggregate productivity shock
    Unemp = [UnempG;UnempB]
    
    # probability of remaining in 'Good/High' productivity state
    πzg = 1.0 - 1.0/DurZG
    
    # probability of remaining in the 'Bad/Low' productivity state
    πzb = 1.0 - 1.0/DurZB
    
    # matrix of transition probabilities for aggregate state
    πz = [πzg 1.0-πzg;
          1.0-πzb πzb]
    
    # transition probabilities between employment states when aggregate productivity is high
    p22 = 1.0 - 1.0 / UnempDurG
    p21 = 1.0 - p22
    p11 = (((1.0 - UnempG) - UnempG * p21) / (1.0 - UnempG))
    #       e    u   for good to good
    P11 = [p11 1.0-p11; 
           p21 p22]
    
    # transition probabilities between employment states when aggregate productivity is low
    p22 = 1.0 - 1.0 / UnempDurB
    p21 = 1.0 - p22
    p11 = (((1.0 - UnempB) - UnempB * p21) / (1.0 - UnempB))
    #       e    u   for bad to bad
    P00 = [p11 1.0-p11; 
           p21 p22] 
    
    # transition probabilities between employment states when aggregate productivity is high
    p22 = (1.0 + Corr) * p22
    p21 = 1.0 - p22
    p11 = (((1.0 - UnempB) - UnempG * p21) / 
           (1.0 - UnempG))
    #       e    u   for good to bad
    P10 = [p11 1.0-p11; 
           p21 p22]

    p22 = (1.0 - Corr) * (1.0 - 1.0 / UnempDurG)
    p21 = 1.0 - p22
    p11 = (((1.0 - UnempG) - UnempB * p21) / 
           (1.0 - UnempB))
    #       e    u   for bad to good
    P01 = [p11 1.0-p11; 
           p21 p22]

    P = [πz[1,1]*P11 πz[1,2]*P10;
         πz[2,1]*P01 πz[2,2]*P00]
    
    states = [gZ empS;gZ unempS;bZ empS;bZ unempS] 
    statesID = [1 1;1 2;2 1; 2 2]
    aggstatesID = [1;1;2;2]
    ns = size(states,1)

    LoMK = [Kg1;Kg2;Kb1;Kb2]
    LoML = [Lg1;Lg2;Lb1;Lb2]

    nis = 2 #number of individual states
    nas = 2 #number of aggregate states
    KSMarkovChain =ModelMarkovChainEnd(states,statesID,aggstatesID,ns,nis,nas,πz,P,[empS;unempS],[gZ;bZ])    

    ##########################################################
    ############### Mesh generation ##########################
    ##########################################################
    function grid_fun(a_min,a_max,na, pexp)
        x = range(a_min,step=0.5,length=na)
        grid = a_min .+ (a_max-a_min)*(x.^pexp/maximum(x.^pexp))
        return grid
    end
    kGrid = grid_fun(0.0,kMax,nk,4.0)
    KGrid = collect(range(KMin,stop = KMax,length=nK))
    #LGrid = range(LMin,stop = LMax,length=nL)
    nkK = nk*nK

    ne = (nk-1)*(nK-1)               #number of elements
    nv = 4                                  #number of values by element (k1,k2,K1,K2,L1,L2)
    
    ElementsID = zeros(I,ne,nv) #element indices
    Elements = zeros(R,ne,nv) #elements

    #Build finite element mesh with node indices (k1,k2,K1,K2,L1,L2) per element
    for ki = 1:nk-1 #across ind k
        for Ki = 1:nK-1 #across agg L
            n = (ki-1)*(nK-1) + Ki  
            ElementsID[n,1],ElementsID[n,2] = ki,ki+1
            ElementsID[n,3],ElementsID[n,4] = Ki,Ki+1
            Elements[n,1],Elements[n,2] = kGrid[ki],kGrid[ki+1]
            Elements[n,3],Elements[n,4] = KGrid[Ki],KGrid[Ki+1]
        end
    end
    QuadratureAbscissas,QuadratureWeights = gausslegendre(NumberOfQuadratureNodesPerElement)
    KSFiniteElement = ModelFiniteElementEnd(Elements,ElementsID,kGrid,KGrid,NumberOfQuadratureNodesPerElement,QuadratureWeights,QuadratureAbscissas,nk,nK,ne)

    #return KSMC, Elements, ElementID
    Guess = zeros(R,nkK*ns)
    #GuessPolicy = zeros(nkKL*ns)

    #@show nkKL*ns
    #solution guess θ for a(k,k̄;θs) at each node on the grid of x
    
    for s=1:ns
        z,ϵ = states[s,1],states[s,2]
        Lb0,Lb1 = LoML[nas*(aggstatesID[s]-1)+1], LoML[nas*(aggstatesID[s]-1)+2]
        Kb0,Kb1 = LoMK[nas*(aggstatesID[s]-1)+1], LoMK[nas*(aggstatesID[s]-1)+2] 
        for (ki,k) in enumerate(kGrid) #ind k
            for (Ki,K) in enumerate(KGrid) #agg k
                ##forecast labor
                L = exp(Lb0 + Lb1*log(K))
                n = (s-1)*nkK + (ki-1)*nK + Ki
                r = α*z*K^(α-1.0)*L^(1.0-α)-d
                w = (1.0-α)*z*K^(α)*L^(-α)
                l = 0.5
                (s == 1 || s == 3) ? c = 0.9 : c = 0.3
                kp = (1.0 + r)*k + w*(1.0 - l)*ϵ + (1.0 - ϵ)*homeY - c
                for j = 1:100 
                    c = (1.0 + r)*k + ϵ*w*(1.0 - l) + (1.0 - ϵ)*homeY - kp
                    ∂c∂l = -ϵ*w
                    ul = (1.0-γ)/γ*1.0/l
                    ull = -1.0*((1.0-γ)/γ)*1.0/l^2.0
                    uc = 1.0/c
                    ucc = -1.0/c^2.0                    
                    mrs = -ul + w*ϵ*uc + ζ*min(1.0 - l,0.0)^2
                    dmrs = -ull + w*ϵ*ucc*∂c∂l - 2.0*ζ*min(1.0 - l,0.0)
                    l += -1.0* mrs/dmrs
                    if abs(mrs/dmrs) < 1e-14
                        break
                    elseif j == 100
                        error("Did not converge")
                    end
                end
                if c < 0.0
                    println(s," ",k)
                end
                Guess[n] = 0.98*kp
            end
        end
    end
    GuessM = reshape(Guess,nK,nk,ns)

    ################### Distribution pieces
    DistributionAssetGrid = collect(range(kGrid[1],stop = kGrid[end],length = NumberOfHouseholds))
    InitialDistribution = rand(nis*NumberOfHouseholds)
    InitialDistribution = InitialDistribution/sum(InitialDistribution)
    InitialDistribution = reshape(InitialDistribution,NumberOfHouseholds,nis)

    mc = MarkovChain(πz, [1, 2])
    AggShocks = simulate(mc,TimePeriods,init=1)

    KSDistribution = ModelDistributionEnd(NumberOfHouseholds,DistributionAssetGrid,InitialDistribution,AggShocks,TimePeriods)

    KSParameters = ModelParametersEnd(β,d,B_,γ,σ,α,ζ,homeY)
    
    KSMarkovFiniteElementEnd(Guess,GuessM,LoMK,LoML,KSParameters,KSFiniteElement,KSMarkovChain,KSDistribution)
end




function WeightedResidualEnd(
    θ::Array{F,1},
    LoMK::Array{R,1},
    LoML::Array{R,1},
    FiniteElementObj::KSMarkovFiniteElementEnd{R,I}) where{R <: Real,I <: Integer,F <: Real}

    @unpack β,d,B_,γ,σ,α,ζ,homeY = FiniteElementObj.Parameters  
    @unpack elements,elementsID,kGrid,KGrid,m,wx,ax,nk,nK,ne = FiniteElementObj.FiniteElement  
    @unpack states,statesID,aggstatesID,ns,nas,Π = FiniteElementObj.MarkovChain  
    l,c,uc,ucc,ul,ull,∂c∂l = 0.5,0.0,0.0,0.0,0.0,0.0,0.0
    lp,cp,ucp,uccp,ulp,ullp = 0.5,0.0,0.0,0.0,0.0,0.0
    
    nkp = 0
    np = 0    
    
    #Dimension of the problem
    nkK = nk*nK
    nx = ns*nkK
    mk,mK = m,m
    Res  = zeros(F,nx) 
    dr = zeros(F,nx,nx)
    for s = 1:ns #for each state in the state space
        z,ϵ = states[s,1],states[s,2]
        Lb0,Lb1 = LoML[nas*(aggstatesID[s]-1)+1], LoML[nas*(aggstatesID[s]-1)+2] 
        Kb0,Kb1 = LoMK[nas*(aggstatesID[s]-1)+1], LoMK[nas*(aggstatesID[s]-1)+2] 
        for n=1:ne #for each element in the finite element mesh
            k1,k2 = elements[n,1],elements[n,2]
            K1,K2 = elements[n,3],elements[n,4]
            ki,Ki = elementsID[n,1],elementsID[n,3] #indices of endog states for policy

            ### NOTE: these indices keep track of which elements solution depends on
            s1,s4 = (s-1)*nkK + (ki-1)*nK + Ki, (s-1)*nkK + (ki-1)*nK + Ki + 1
            s2,s3 = (s-1)*nkK + ki*nK + Ki, (s-1)*nkK + ki*nK + Ki + 1
            for mki = 1:mk #integrate across k
                k = (k1 + k2)/2.0 + (k2 - k1)/2.0 * ax[mki] #use Legendre's rule
                kv = (k2-k1)/2.0*wx[mki]
                for mKi = 1:mK #integrate across k̄
                    K = (K1 + K2)/2.0 + (K2 - K1)/2.0 * ax[mKi] #use Legendre's rul
                    Kv = (K2-K1)/2.0*wx[mKi]

                    #labor law of motion
                    L = exp(Lb0 + Lb1*log(K))
                    
                    #Get functions of agg variables
                    r = α*z*(K/L)^(α-1.0) - d 
                    w = (1.0-α)*z*(K/L)^α

                    #Form basis for piecewise function
                    basis1 = (k2 - k)/(k2 - k1) * (K2 - K)/(K2 - K1)
                    basis2 = (k - k1)/(k2 - k1) * (K2 - K)/(K2 - K1)
                    basis3 = (k - k1)/(k2 - k1) * (K - K1)/(K2 - K1)
                    basis4 = (k2 - k)/(k2 - k1) * (K - K1)/(K2 - K1)                       

                    #Policy functions 
                    kp = θ[s1]*basis1 + θ[s2]*basis2 + 
                             θ[s3]*basis3 + θ[s4]*basis4
                    
                    pen = ζ*min(kp,0.0)^2
                    dpen = 2.0*ζ*min(kp,0.0)

                    l = 0.7
                    ##solve for labor
                    for j = 1:100 
                        c = (1.0 + r)*k + ϵ*w*(1.0 - l) + (1.0 - ϵ)*homeY - kp
                        ∂c∂l = -ϵ*w
                        ul = (1.0-γ)/γ*1.0/l
                        ull = -1.0*((1.0-γ)/γ)*1.0/l^2.0
                        uc = 1.0/c
                        ucc = -1.0/c^2.0                    
                        mrs = ul - w*ϵ*uc - ζ*min(1.0 - l,0.0)^2
                        dmrs = ull - w*ϵ*ucc*∂c∂l + 2.0*ζ*min(1.0 - l,0.0)
                        l += -1.0* mrs/dmrs
                        if abs(mrs/dmrs) < 1e-14
                            break
                        elseif j == 100
                            error("mrs did not converge")
                        end
                    end
                    #@show s
                    #@show K
                    #@show k
                    #@show kp
                    #@show l
                    
                    ∂l∂ki = -w*ϵ*ucc/(2.0*ζ*min(1.0 - l,0.0) + ull + (w*ϵ)^2*ucc)
                    ∂c∂ki = -ϵ*w*∂l∂ki - 1.0
                    if c < 0.0
                        error("cons neg")
                    end
                    #LOM for agg capital 
                    Kp = exp(Kb0 + Kb1*log(K))

                    #Find the element it belongs to
                    for i = 1:ne
                        if (kp>=elements[i,1] && kp<=elements[i,2]) 
                            nkp = i     
                            break
                        elseif kp<elements[1,1]
                            nkp = 1
                            break
                        else
                            nkp = ne-nk
                        end
                    end
                    # Find the aggregate state and adjust if it falls outside the grid
                    for j = nkp:nkp+nK-2
                        if (Kp >= elements[j,3] && Kp <= elements[j,4]) 
                            np = j     
                            break
                        elseif Kp < elements[nkp,3]
                            np = nkp
                            break
                        else
                            np = nkp+nK-2
                        end
                    end
                    
                    kp1,kp2 = elements[np,1],elements[np,2]
                    Kp1,Kp2 = elements[np,3],elements[np,4]
                    kpi,Kpi = elementsID[np,1],elementsID[np,3] #indices of endog states for policy

                    basisp1 = (kp2 - kp)/(kp2 - kp1) * (Kp2 - Kp)/(Kp2 - Kp1)
                    basisp2 = (kp - kp1)/(kp2 - kp1) * (Kp2 - Kp)/(Kp2 - Kp1)
                    basisp3 = (kp - kp1)/(kp2 - kp1) * (Kp - Kp1)/(Kp2 - Kp1)
                    basisp4 = (kp2 - kp)/(kp2 - kp1) * (Kp - Kp1)/(Kp2 - Kp1)

                    ####### Store derivatives###############
                    dbasisp1 = -1.0/(kp2 - kp1) * (Kp2 - Kp)/(Kp2 - Kp1) 
                    dbasisp2 =  1.0/(kp2 - kp1) * (Kp2 - Kp)/(Kp2 - Kp1)
                    dbasisp3 =  1.0/(kp2 - kp1) * (Kp - Kp1)/(Kp2 - Kp1)
                    dbasisp4 = -1.0/(kp2 - kp1) * (Kp - Kp1)/(Kp2 - Kp1)

                    tsai = 0.0
                    sum1 = 0.0 
                    for sp = 1:ns 
                        sp1,sp4 = (sp-1)*nkK + (kpi-1)*nK + Kpi, (sp-1)*nkK + (kpi-1)*nK + Kpi + 1
                        sp2,sp3 = (sp-1)*nkK + kpi*nK + Kpi, (sp-1)*nkK + kpi*nK + Kpi + 1
                        zp,ϵp = states[sp,1],states[sp,2]

                        Lb0p,Lb1p = LoML[nas*(aggstatesID[sp]-1)+1], LoML[nas*(aggstatesID[sp]-1)+2]
                        Lp = exp(Lb0p + Lb1p*log(Kp))

                        #Get functions of agg variables
                        rp = α*zp*(Kp/Lp)^(α-1.0) - d
                        wp = (1.0-α)*zp*(Kp/Lp)^α

                        #Policy functions
                        kpp = θ[sp1]*basisp1 + θ[sp2]*basisp2 + 
                                  θ[sp3]*basisp3 + θ[sp4]*basisp4

                        lp = 0.5
                        for j = 1:100
                            cp = (1.0 + rp)*kp + ϵp*wp*(1.0 - lp) + (1.0 - ϵp)*homeY - kpp
                            ∂cp∂lp = -ϵp*wp
                            ulp = (1.0-γ)/γ*1.0/lp
                            ullp = -1.0*(1.0-γ)/γ*1.0/lp^2
                            ucp = 1.0/cp
                            uccp = -1.0/cp^2.0                    
                            mrsp = ulp - wp*ϵp*ucp - ζ*min(1.0 - lp,0.0)^2
                            dmrsp = ullp - wp*ϵp*uccp*∂cp∂lp + 2.0*ζ*min(1.0 - lp,0.0)
                            lp += -1.0* mrsp/dmrsp
                            if abs(mrsp/dmrsp) < 1e-14
                                break
                            elseif j == 100
                                error("Did not converge")
                            end
                        end
                        ∂kpp∂ki = θ[sp1]*dbasisp1 + θ[sp2]*dbasisp2 +
                            θ[sp3]*dbasisp3 + θ[sp4]*dbasisp4
                        ∂lp∂ki = (1.0 + rp - ∂kpp∂ki)*uccp*wp*ϵp/(ullp + uccp*(wp*ϵp)^2 + 2.0*ζ*min(1.0 - lp,0.0))
                        ∂cp∂ki = (1.0 + rp) - ϵp*wp*∂lp∂ki - ∂kpp∂ki
                        ∂lp∂kj = -uccp*wp*ϵp/(ullp + uccp*(wp*ϵp)^2 + 2.0*ζ*min(1.0 - lp,0.0))
                        ∂cp∂kj = -ϵp*wp*∂lp∂kj - 1.0
                        sum1 += β*Π[s,sp]*(1.0 + rp)*ucp + pen 

                        #derivatives of kp have θi associated with kp
                        tsai += β*Π[s,sp]*(1.0 + rp)*uccp*∂cp∂ki + dpen                                
                        #derivatives of kpp wrt kp have θj associated with kpp
                        tsaj = β*Π[s,sp]*(1.0 + rp)*uccp*∂cp∂kj 

                        dr[s1,sp1] +=  basis1 * kv * Kv * tsaj * basisp1
                        dr[s1,sp2] +=  basis1 * kv * Kv * tsaj * basisp2
                        dr[s1,sp3] +=  basis1 * kv * Kv * tsaj * basisp3
                        dr[s1,sp4] +=  basis1 * kv * Kv * tsaj * basisp4
                        dr[s2,sp1] +=  basis2 * kv * Kv * tsaj * basisp1
                        dr[s2,sp2] +=  basis2 * kv * Kv * tsaj * basisp2
                        dr[s2,sp3] +=  basis2 * kv * Kv * tsaj * basisp3
                        dr[s2,sp4] +=  basis2 * kv * Kv * tsaj * basisp4
                        dr[s3,sp1] +=  basis3 * kv * Kv * tsaj * basisp1
                        dr[s3,sp2] +=  basis3 * kv * Kv * tsaj * basisp2
                        dr[s3,sp3] +=  basis3 * kv * Kv * tsaj * basisp3
                        dr[s3,sp4] +=  basis3 * kv * Kv * tsaj * basisp4
                        dr[s4,sp1] +=  basis4 * kv * Kv * tsaj * basisp1
                        dr[s4,sp2] +=  basis4 * kv * Kv * tsaj * basisp2
                        dr[s4,sp3] +=  basis4 * kv * Kv * tsaj * basisp3
                        dr[s4,sp4] +=  basis4 * kv * Kv * tsaj * basisp4

                    end
                    #add the LHS and RHS of euler for each s wrt to θi
                    dres =  tsai - ucc*∂c∂ki 

                    dr[s1,s1] +=  basis1 * kv * Kv * dres * basis1
                    dr[s1,s2] +=  basis1 * kv * Kv * dres * basis2
                    dr[s1,s3] +=  basis1 * kv * Kv * dres * basis3
                    dr[s1,s4] +=  basis1 * kv * Kv * dres * basis4
                    dr[s2,s1] +=  basis2 * kv * Kv * dres * basis1
                    dr[s2,s2] +=  basis2 * kv * Kv * dres * basis2
                    dr[s2,s3] +=  basis2 * kv * Kv * dres * basis3
                    dr[s2,s4] +=  basis2 * kv * Kv * dres * basis4
                    dr[s3,s1] +=  basis3 * kv * Kv * dres * basis1
                    dr[s3,s2] +=  basis3 * kv * Kv * dres * basis2
                    dr[s3,s3] +=  basis3 * kv * Kv * dres * basis3
                    dr[s3,s4] +=  basis3 * kv * Kv * dres * basis4
                    dr[s4,s1] +=  basis4 * kv * Kv * dres * basis1
                    dr[s4,s2] +=  basis4 * kv * Kv * dres * basis2
                    dr[s4,s3] +=  basis4 * kv * Kv * dres * basis3
                    dr[s4,s4] +=  basis4 * kv * Kv * dres * basis4
                    
                    res = sum1 - uc
                    Res[s1] += basis1 * kv * Kv * res
                    Res[s2] += basis2 * kv * Kv * res  
                    Res[s3] += basis3 * kv * Kv * res 
                    Res[s4] += basis4 * kv * Kv * res 
                end
            end
        end
    end
   Res,dr
end

function SolveFiniteElementEnd(
    guess::Array{R,1},
    LoMK::Array{R,1},
    LoML::Array{R,1},
    FiniteElementObj::KSMarkovFiniteElementEnd{R,I},
    maxn::Int64 = 1000,
    tol = 1e-9
) where{R <: Real,I <: Integer}

    θ = guess
    #Newton Iteration
    for i = 1:100
        Res,dRes = WeightedResidualEnd(θ,LoMK,LoML,FiniteElementObj)
        #dRes = ForwardDiff.jacobian(t -> WeightedResidualEnd(t,LoMK,LoML,FiniteElementObj)[1], Guess)
        step = - dRes \ Res
        if LinearAlgebra.norm(step) > 1.0
            θ += 1.0/10.0*step
        else
            θ += 1.0/1.0*step
        end
        @show LinearAlgebra.norm(step)
        if LinearAlgebra.norm(step) < tol
            return θ
            break
        end
    end
        
    return θ
end



KS = KSModelEnd()
@unpack Guess,GuessM,LoMK,LoML = KS



##############Jacobian tests
######################################
#jacobian = zeros(ResidualSize,ResidualSize)
#jacobian = WeightedResidualEnd(Guess,LoMK,LoML,KS)[2]
#jacobian2 =  ForwardDiff.jacobian(x -> WeightedResidualEnd(x,LoMK,LoML,KS)[1],Guess)
#@show LinearAlgebra.norm(jacobian - jacobian2,Inf)
#show(IOContext(STDOUT, limit = true,displaysize = (400,400)), "text/plain", jacobian[:,11:20] - jacobian2[:,11:20])


@unpack kGrid,nk,nK = KS.FiniteElement
@unpack ns = KS.MarkovChain
p1 = plot(kGrid,GuessM[1,:,1], label = "high employed", linewidth = 0.5)
p1 = plot!(kGrid,GuessM[1,:,2], label = "high unemployed", linewidth = 0.5)
p1 = plot!(kGrid,GuessM[1,:,3], label = "low employed" , linewidth = 0.5)
p1 = plot!(kGrid,GuessM[1,:,4], label = "low unemployed", linewidth = 0.5)
p1 = plot!(kGrid,kGrid, line = :dot, label = "45 degree line")
#p1 = plot!(xlims = (0.0,50.0), ylims=(0.0,50.0))
p1 = plot!(title = "low agg capital guess")

#savefig(p1,"PoliciesSolGuess.pdf")

#a,b = WeightedResidualEnd(Guess,LoMK,LoML,KS)
#pol = SolveFiniteElementEnd(Guess,LoMK,LoML,KS)


#a,b = WeightedResidualEnd(Guess,LoMK,LoML,KS)
#pol = SolveFiniteElementEnd(Guess,LoMK,LoML,KS)
#θ0,LoMK,LoML,Kt,Lt,Prob0 =  KSEquilibriumEnd(KS)

pol = SolveFiniteElementEnd(Guess,LoMK,LoML,KS)
polr = reshape(pol,nK,nk,ns)
p2 = plot(kGrid,polr[1,:,1], label = "high employed", linewidth = 0.5)
p2 = plot!(kGrid,polr[1,:,2], label = "high unemployed", linewidth = 0.5)
p2 = plot!(kGrid,polr[1,:,3], label = "low employed" , linewidth = 0.5)
p2 = plot!(kGrid,polr[1,:,4], label = "low unemployed", linewidth = 0.5)
p2 = plot!(kGrid,kGrid, line = :dot, label = "45 degree line")
#p2 = plot!(xlims = (0.0,50.0), ylims=(0.0,50.0))
p2 = plot!(title = "low agg capital solution")
p = plot(p1,p2, layout = (1,2), legend = false)
savefig(p,"PoliciesSolGuess.pdf")















function NextPeriodDistributionEnd(
    Φ::Array{R,2},
    AggStateToday::I,
    AggStateTomorrow::I,
    θ::Array{F,1},
    FiniteElementObj::KSMarkovFiniteElementEnd{R,I}) where{R <: Real,I <: Integer,F <: Real}

    @unpack elements,elementsID,nk,nK,ne = FiniteElementObj.FiniteElement  
    @unpack states,IndStates,AggStates,statesID,aggstatesID,ns,nis,Π =FiniteElementObj.MarkovChain 
    @unpack DistributionSize,DistributionAssetGrid,TimePeriods = FiniteElementObj.Distribution

    ####Aggregate conditions today and transition to tomorrow
    nkK = nk*nK
    #FullGrid = vcat(DistributionAssetGrid,DistributionAssetGrid)
    K = dot(Φ[:,1],DistributionAssetGrid) + dot(Φ[:,2],DistributionAssetGrid)
    z  = ifelse(AggStateToday == 1, [1,2], [3,4])
    zp = ifelse(AggStateTomorrow == 1, [1,2], [3,4])
    Πz = Π[z,zp]

    Φp = fill(0.0,size(Φ))
    n,nki = 0,0
    for is = 1:nis
        (is == 1 && AggStateToday == 1) ? s = 1 :
            (is == 2 && AggStateToday == 1) ? s = 2 :
                (is == 1 && AggStateToday == 2) ? s = 3 : s = 4
        for (ki,k) in enumerate(DistributionAssetGrid)
            for i = 1:ne
                if (k>=elements[i,1] && k<=elements[i,2]) 
                    nki = i     
                    break
                elseif k<elements[1,1]
                    nki = 1
                    break
                else
                    nki = ne-nk
                end
            end
            # Find the aggregate state and adjust if it falls outside the grid
            for j = nki:nki+nK-2
                if (K >= elements[j,3] && K <= elements[j,4]) 
                    n = j     
                    break
                elseif K < elements[nki,3]
                    n = nki
                    break
                else
                    n = nki+nK-2
                end
            end
            k1,k2 = elements[n,1],elements[n,2]
            K1,K2 = elements[n,3],elements[n,4]
            kii,Ki = elementsID[n,1],elementsID[n,3] #indices of endog states for policy
            s1,s4 = (s-1)*nkK + (kii-1)*nK + Ki, (s-1)*nkK + (kii-1)*nK + Ki + 1
            s2,s3 = (s-1)*nkK + kii*nK + Ki, (s-1)*nkK + kii*nK + Ki + 1

            basis1 = (k2 - k)/(k2 - k1) * (K2 - K)/(K2 - K1)
            basis2 = (k - k1)/(k2 - k1) * (K2 - K)/(K2 - K1)
            basis3 = (k - k1)/(k2 - k1) * (K - K1)/(K2 - K1)
            basis4 = (k2 - k)/(k2 - k1) * (K - K1)/(K2 - K1)

            #Policy functions 
            kp = θ[s1]*basis1 + θ[s2]*basis2 + θ[s3]*basis3 + θ[s4]*basis4

            np = searchsortedlast(DistributionAssetGrid,kp)
            if (np > 0) && (np < DistributionSize)
                h1 = DistributionAssetGrid[np]
                h2 = DistributionAssetGrid[np+1]
            end

            
            Πtot = Πz[is,1]+Πz[is,2]
            if np == 0
                #println("negative savings: ",k," ",is)
                Φp[np+1,1] += (Πz[is,1]/Πtot)*Φ[ki,is]  ##1st employed agent 
                Φp[np+1,2] += (Πz[is,2]/Πtot)*Φ[ki,is] #1st unemployed agent
            elseif np == DistributionSize
                #println("savings beyond grid: ",k," ",is)
                Φp[np,1] += (Πz[is,1]/Πtot)*Φ[ki,is]
                Φp[np,2] += (Πz[is,2]/Πtot)*Φ[ki,is]
            else
                # status is kp, employed
                ω = 1.0 - (kp-h1)/(h2-h1)
                Φp[np,1] += (Πz[is,1]/Πtot)*ω*Φ[ki,is]
                Φp[np+1,1] += (Πz[is,1]/Πtot)*(1.0 - ω)*Φ[ki,is]
                # status is kp, unemployed
                Φp[np,2] += (Πz[is,2]/Πtot)*ω*Φ[ki,is]
                Φp[np + 1,2] += (Πz[is,2]/Πtot)*(1.0 - ω)*Φ[ki,is]
            end
        end
    end

    return Φp
end

function KSEquilibriumEnd(FiniteElementObj::KSMarkovFiniteElementEnd{R,I}) where{R <: Real,I <: Integer,F <: Real}
    @unpack β,d,B_,γ,σ,α,ζ,homeY = FiniteElementObj.Parameters
    @unpack elements,elementsID,nk,nK,ne = FiniteElementObj.FiniteElement
    @unpack states,IndStates,AggStates,statesID,aggstatesID,nis =FiniteElementObj.MarkovChain
    @unpack DistributionSize, DistributionAssetGrid,InitialDistribution,AggShocks,TimePeriods = FiniteElementObj.Distribution
    l,c,uc,ucc,ul,ull,∂c∂l = 0.5,0.0,0.0,0.0,0.0,0.0,0.0
    lp,cp,ucp,uccp,ulp,ullp = 0.5,0.0,0.0,0.0,0.0,0.0

    Rsqrd = fill(0.0, (4,))
    n_discard = 500
    n,nki = 0,0
    nkK = nk*nK
    
    #Initial guess
    θ0 = FiniteElementObj.Guess
    #FullGrid = vcat(DistributionAssetGrid,DistributionAssetGrid)
    θ0 = SolveFiniteElementEnd(θ0,LoMK,LoML,FiniteElementObj)
    
    #Get stationary distribution to start iteration
    Φ = InitialDistribution
    for i = 1:(TimePeriods-1)   
        Φ = NextPeriodDistributionEnd(Φ,AggShocks[i],AggShocks[i+1],θ0,FiniteElementObj)
    end
    #Initial law of motion
    LoM = vcat(FiniteElementObj.LoMK,FiniteElementObj.LoML)
    
    ###Iterate on law of motion
    for i = 1:200
        #create time series vectors
        Kt = fill(0.0, (TimePeriods,))
        Lt = fill(0.0, (TimePeriods,))

        LoMK,LoML = LoM[1:4],LoM[5:8]
        #solve individual problem
        θ0 = SolveFiniteElementEnd(θ0,LoMK,LoML,FiniteElementObj)
        @show Kt[1] = dot(Φ[:,1],DistributionAssetGrid) + dot(Φ[:,2],DistributionAssetGrid)
        #Build time series
        for t = 1:(TimePeriods-1)
            AggStateToday = AggShocks[t]
            #Aggragate variables today
            z = AggStates[AggStateToday]
            K = Kt[t]

            #labor guess
            L = 0.4

            #solve for labor that clears market L
            for li = 1:100
                Ls,∂Ls∂L = 0.0,0.0
                r = α*z*(K/L)^(α-1.0) - d
                w = (1.0-α)*z*(K/L)^α 
                ∂r∂L = α*(1.0-α)*K^(α-1.0)*L^(-α)
                ∂w∂L = (1.0-α)*(-α)*K^α*L^(-α-1.0)
                for (is,ϵ) = enumerate(IndStates)
                    (is == 1 && AggStateToday == 1) ? s = 1 :
                        (is == 2 && AggStateToday == 1) ? s = 2 :
                            (is == 1 && AggStateToday == 2) ? s = 3 : s = 4
                    for (ki,k) in enumerate(DistributionAssetGrid)
                        for i = 1:ne
                            if (k>=elements[i,1] && k<=elements[i,2]) 
                                nki = i     
                                break
                            elseif k<elements[1,1]
                                nki = 1
                                break
                            else
                                nki = ne-nk
                            end
                        end
                        # Find the aggregate state and adjust if it falls outside the grid
                        for j = nki:nki+nK-2
                            if (K >= elements[j,3] && K <= elements[j,4]) 
                                n = j     
                                break
                            elseif K < elements[nki,3]
                                n = nki
                                break
                            else
                                n = nki+nK-2
                            end
                        end
                        k1,k2 = elements[n,1],elements[n,2]
                        K1,K2 = elements[n,3],elements[n,4]
                        kii,Ki = elementsID[n,1],elementsID[n,3] #indices of endog states for policy
                        s1,s4 = (s-1)*nkK + (kii-1)*nK + Ki, (s-1)*nkK + (kii-1)*nK + Ki + 1
                        s2,s3 = (s-1)*nkK + kii*nK + Ki, (s-1)*nkK + kii*nK + Ki + 1

                        basis1 = (k2 - k)/(k2 - k1) * (K2 - K)/(K2 - K1)
                        basis2 = (k - k1)/(k2 - k1) * (K2 - K)/(K2 - K1)
                        basis3 = (k - k1)/(k2 - k1) * (K - K1)/(K2 - K1)
                        basis4 = (k2 - k)/(k2 - k1) * (K - K1)/(K2 - K1)

                        #Policy functions 
                        kp = θ0[s1]*basis1 + θ0[s2]*basis2 + θ0[s3]*basis3 + θ0[s4]*basis4
                        if ϵ == 1.0   
                            l = (1.0-γ) * ((1.0 + r)*k + w - kp) / w
                            if l > 1.0
                                l = 1.0
                                #print("high l")
                            end
                            c = (1.0 + r)*k + (1.0-l)*w - kp
                        else
                            l = 1.0
                            c = (1.0 + r)*k + homeY - kp
                        end
                        ul = (1.0-γ)/γ*1.0/l
                        ull = -1.0*((1.0-γ)/γ)*1.0/l^2.0
                        uc = 1.0/c
                        ucc = -1.0/c^2.0                    
                        pk = Φ[ki,is]
                        Ls += Φ[ki,is]*(1.0 - l)*ϵ
                        ∂l∂L = (∂w∂L*ϵ*uc + w*ϵ*ucc*((1.0-l)*ϵ*∂w∂L + ∂r∂L*k))/(ull + (w*ϵ)^2.0*ucc + 2.0*ζ*min(1.0 - l,0.0))
                        ∂Ls∂L += -Φ[ki,is]*ϵ*∂l∂L
                    end
                end
                df = ∂Ls∂L - 1.0
                f = Ls - L
                step = -f/df
                L += step
                if abs(step) < 1e-5
                    break
                elseif li == 100
                    error("labor supply did not clear ",t)
                end
            end
            #@show AggStateToday
            #@show sum(Φ[DistributionSize+1:2*DistributionSize])/sum(Φ)
            Lt[t] = L
            Φ = NextPeriodDistributionEnd(Φ,AggShocks[t],AggShocks[t+1],θ0,FiniteElementObj)
            Kt[t+1] = dot(Φ[:,1],DistributionAssetGrid) + dot(Φ[:,2],DistributionAssetGrid)
        end
        
        #return Kt,Lt
        
        ###Get indices of agg states
        n_g=count(i->(i==1),AggShocks[n_discard+1:end-1]) #size with good periods after discard
        n_b=count(i->(i==2),AggShocks[n_discard+1:end-1]) #size with bad periods after discard
        x_g=Vector{Float64}(n_g) #RHS of good productivity reression
        yk_g=Vector{Float64}(n_g) #LHS of good productivity reression
        yl_g=Vector{Float64}(n_g)
        x_b=Vector{Float64}(n_b) #RHS of bad productivity reression
        yk_b=Vector{Float64}(n_b) #LHS of bad productivity reression
        yl_b=Vector{Float64}(n_b)
        i_g=0
        i_b=0
        for t = n_discard+1:length(AggShocks)-1
            if AggShocks[t]==1
                i_g=i_g+1
                x_g[i_g]=log(Kt[t])
                yk_g[i_g]=log(Kt[t+1])
                yl_g[i_g]=log(Lt[t])
            else
                i_b=i_b+1
                x_b[i_b]=log(Kt[t])
                yk_b[i_b]=log(Kt[t+1])
                yl_b[i_b]=log(Lt[t])
            end
        end

        reskg=lm(hcat(ones(n_g,1),x_g),yk_g)
        reskb=lm(hcat(ones(n_b,1),x_b),yk_b)
        reslg=lm(hcat(ones(n_g,1),x_g),yl_g)
        reslb=lm(hcat(ones(n_b,1),x_b),yl_b)

        LoMKnew = fill(0.0,size(LoMK))
        LoMLnew = fill(0.0,size(LoML))
        @show Rsqrd[1]= r2(reskg)
        @show Rsqrd[2]= r2(reskb)
        @show Rsqrd[3]= r2(reslg)
        @show Rsqrd[4]= r2(reslb)

        LoMKnew[1:2] = coef(reskg)
        LoMKnew[3:4] = coef(reskb)
        LoMLnew[1:2] = coef(reslg)
        LoMLnew[3:4] = coef(reslb)
        LoMnew = vcat(LoMKnew,LoMLnew)
        
        if  LinearAlgebra.norm(LoMnew - LoM,Inf) < 0.00001
            println("Equilibrium found")
            return θ0,LoMKnew,LoMLnew,Kt,Lt,Φ
            break
        else
            @show LoM = 0.2*LoMnew + 0.8*LoM
        end
    end
end


function Policies(
    kStream::Array{R,1},
    K::R,
    θ::Array{F,1},
    LoMK::Array{R,2},
    FiniteElementObj::KSMarkovFiniteElementEnd{R,I}) where{R <: Real,I <: Integer,F <: Real}

    @unpack β,d,B_,γc,γl,α,ζ,homeY,hfix = FiniteElementObj.Parameters  
    @unpack elements,elementsID,zGrid,KGrid,nz,nK,ne = FiniteElementObj.FiniteElement  
    @unpack states,IndStates,AggStates,statesID,aggstatesID,ns,nis,nas,πz,Π,LoML =FiniteElementObj.MarkovChain 

    #some helpful parameters
    nzK = nz*nK    

    #policies
    cPol = fill(0.0,(length(kStream),ns))
    kpPol = fill(0.0,(length(kStream),ns))
    


    nki=0
    n=0    
    for s = 1:ns
        A,ϵ = states[s,1],states[s,2]
        L = LoML[aggstatesID[s]] 
        Kb0,Kb1 = LoMK[aggstatesID[s],1], LoMK[aggstatesID[s],2]
        r = α*A*(K/L)^(α-1.0) - d 
        w = (1.0-α)*A*(K/L)^α
        for (ki,k) in enumerate(kStream)
            z = w*ϵ*hfix + homeY*(1.0 - ϵ) + (1.0 + r)*k - r*B_
            for i = 1:ne
                if (z>=elements[i,1] && z<=elements[i,2]) 
                    nki = i     
                    break
                elseif z<elements[1,1]
                    nki = 1
                    break
                else
                    nki = ne-nz
                end
            end
            # Find the aggregate state and adjust if it falls outside the grid
            for j = nki:nki+nK-2
                if (K >= elements[j,3] && K <= elements[j,4]) 
                    n = j     
                    break
                elseif K < elements[nki,3]
                    n = nki
                    break
                else
                    n = nki+nK-2
                end
            end

            z1,z2 = elements[n,1],elements[n,2]
            K1,K2 = elements[n,3],elements[n,4]
            zii,Ki = elementsID[n,1],elementsID[n,3] #indices of endog states for policy
            s1,s4 = (s-1)*nzK + (zii-1)*nK + Ki, (s-1)*nzK + (zii-1)*nK + Ki + 1
            s2,s3 = (s-1)*nzK + zii*nK + Ki, (s-1)*nzK + zii*nK + Ki + 1

            basis1 = (z2 - z)/(z2 - z1) * (K2 - K)/(K2 - K1)
            basis2 = (z - z1)/(z2 - z1) * (K2 - K)/(K2 - K1)
            basis3 = (z - z1)/(z2 - z1) * (K - K1)/(K2 - K1)
            basis4 = (z2 - z)/(z2 - z1) * (K - K1)/(K2 - K1)

            #Policy functions 
            kp = θ[s1]*basis1 + θ[s2]*basis2 + θ[s3]*basis3 + θ[s4]*basis4

            cPol[ki,s] = z - kp
            kpPol[ki,s] = kp
            if kp < k && (s == 1 || s == 3)
                println("disavings at k = ",k," ",s)
            end
        end
    end
  
    return cPol,kpPol
end


####initial model 
KS = KSModelEnd()
@unpack Guess,GuessM,LoMK,LoML = KS   
@unpack kGrid,nk,nK = KS.FiniteElement
@unpack ns = KS.MarkovChain


#plot a guess to see how if guess makes sense, adjust if it doesn't
p1 = plot(kGrid,GuessM[1,:,1], label = "high employed", linewidth = 0.5)
p1 = plot!(kGrid,GuessM[1,:,2], label = "high unemployed", linewidth = 0.5)
p1 = plot!(kGrid,GuessM[1,:,3], label = "low employed" , linewidth = 0.5)
p1 = plot!(kGrid,GuessM[1,:,4], label = "low unemployed", linewidth = 0.5)
p1 = plot!(kGrid,kGrid, line = :dot, label = "45 degree line")
p1 = plot!(title = "low agg capital guess")

####### Solve for equilibrium
@time θ0,LoMK,LoML,Kt,Lt,Prob0 =  KSEquilibriumEnd(KS)

###plot equilibrium policies
pol = SolveFiniteElementEnd(θ0,LoMK,LoML,KS)
polr = reshape(pol,nK,nk,ns)
p2 = plot(kGrid,polr[1,:,1], label = "high employed", linewidth = 0.5)
p2 = plot!(kGrid,polr[1,:,2], label = "high unemployed", linewidth = 0.5)
p2 = plot!(kGrid,polr[1,:,3], label = "low employed" , linewidth = 0.5)
p2 = plot!(kGrid,polr[1,:,4], label = "low unemployed", linewidth = 0.5)
p2 = plot!(kGrid,kGrid, line = :dot, label = "45 degree line")
p2 = plot!(xlims = (0.0,10.0), ylims=(0.0,10.0))
p2 = plot!(title = "low agg capital solution")

###plot laws of motion for capital and labor
@unpack InitialDistribution,AggShocks,DistributionAssetGrid, DistributionSize = KS.Distribution
Ktr = fill(0.0,size(Kt))
Ltr = fill(0.0,size(Kt))
Ktr[1] = Kt[1]
for i = 1:length(Ktr)-1
    if AggShocks[i] == 1
        LoMKp = LoMK[1:2]
        LoMLp = LoML[1:2]
    else
        LoMKp = LoMK[3:4]
        LoMLp = LoML[3:4]
    end
    bk0,bk1 = LoMKp[1],LoMKp[2]
    bl0,bl1 = LoMLp[1],LoMLp[2]
    
    Ktr[i+1] =exp(bk0 + bk1*log(Kt[i]))
    Ltr[i] =exp(bl0 + bl1*log(Kt[i]))
end

p3 = plot(Ktr[1:500], label = "LOM")
p3 = plot!(Kt[1:500], label = "Implied LOM by Individual choice")
p4 = plot(Ltr[1:500], label = "LOM")
p4 = plot!(Lt[1:500], label = "Implied LOM by Individual choice")


####plot distribution
p1 = plot(title= "Distribution")
Prob0 = NextPeriodDistributionEnd(Prob0,AggShocks[1],AggShocks[2],pol,KS)
p1 = plot!(DistributionAssetGrid,Prob0[:,1], label="employed")
p1 = plot!(DistributionAssetGrid,Prob0[:,2], label="unemployed")
p1 = plot!(xlims = (0.0,30.0))
p = plot(p1,p2,p3,p4, layout = (2,2))
p = plot!(titlefont = ("Helvetica",6))
p = plot!(legendfont = ("Helvetica",4))
savefig(p,"endlaborks.pdf")



