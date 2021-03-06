include("ssCollocation.jl")


RM = Reiters(0.02,0.3)


#=Residual(RM.Guess,0.02,RM) 
pol = SolveCollocation(RM.Guess,0.02,RM)
polr = reshape(pol,RM.Collocation.na,RM.MarkovChain.ns)
p1 = plot(RM.Collocation.aGrid,polr[:,1], label="employed")
p1 = plot!(RM.Collocation.aGrid,polr[:,2], label="unemployed")
p1 = plot!(RM.Collocation.aGrid,RM.Collocation.aGrid, line = :dot, label="45 degree line")
p1 = plot!(xlims=(0.0,1.0),ylims=(0.0,1.0))



AvgA,Dist = StationaryDistribution(0.02,pol,RM)
Distr = reshape(Dist,RM.Distribution.DistributionSize,RM.MarkovChain.ns)
p2 = plot(RM.Distribution.DistributionAssetGrid,Distr[:,1], label="employed")
p2 = plot!(RM.Distribution.DistributionAssetGrid,Distr[:,2], label="unemployed")
p = plot(p1,p2, layout = (1,2))
savefig(p,"solution.pdf")
=#

θeq,weq,req,Leq,Keq,cpol,lpol,appol,disteq = equilibrium(RM)

yss = [θeq;θeq;disteq;log(1.0);disteq;log(1.0);fill(0.0,(RM.Collocation.na*RM.MarkovChain.ns,));0.0]
reiter_eqn_builder(yss,lpol,RM)
jac = ForwardDiff.jacobian(t -> reiter_eqn_builder(t,lpol,RM),yss)
#@show LinearAlgebra.norm(jac)
include("gensysJoao.jl")


"""
Take Solution from ayiagari, ie equilibrium distribution, solution at collocation nodes, equilibrium aggregate capital and aggregate labor. Transform the system into the Sims (2001) rational expectations system

X_t = (c_t,λ_t,logA,E(c_t+1))
p = plot(disGrid,dis[:,:,1],xlims=(0.0,10))
for i = 2:30:100
    p = plot!(disGrid,dis[:,:,i],xlims=(0.0,10))
end
savefig(p,"disOverTime.pdf")


Construct

Γ0*Y_t = Γ1*y_t-1 + C + Ψ*z_t + Π*η_t

Solve for A,B s.t. through Gensys from Sims (2001)

X_t = A*X_t-1 + B*ϵ_t 

In terms of the variables in gensys:

y(t)= G1*y(t-1)+C+impact*z(t)+ywt*inv(I-fmat*inv(L))*fwt*z(t+1)

y = (θ), x = (Φ,z)
"""
function RationalExpectations(
    θ::Array{R,1},
    Distribution::Array{R,1},
    ssLabor::Array{F,2},
    ReiterObj::ReiterMethod{F,I}) where {I <: Integer,R <: Real,F <: Real}

    @unpack aGrid,na = ReiterObj.Collocation  
    @unpack states,ns,stateID,Π = ReiterObj.MarkovChain
    @unpack DistributionSize, DistributionAssetGrid = ReiterObj.Distribution

    nfa = na*ns
    nf = DistributionSize*ns
    
    ### Evaluate jacobian of equilibrium conditions  at steady state
    yss = [θ;θ;Distribution;log(1.0);Distribution;log(1.0);fill(0.0,(na*ns,));0.0]
    jac = ForwardDiff.jacobian(t -> reiter_eqn_builder(t,ssLabor,ReiterObj),yss)

    #Distributions are states, individual policies are controls    
    #Remove last row with exogenous shocks
    #Nxp,Nx,Nϵ,Nη = nf+1+nfa,nf+1+nfa,1,nfa
    Ny,Nx,Nϵ,Nη = nfa,nf+1,1,nfa
    VarId = Dict{Symbol,UnitRange{I}}()
    VarId[:yp] = 1:Ny
    VarId[:y]  = Ny+1:2*Ny
    VarId[:xp] = 2*Ny+1:2*Ny+Nx
    VarId[:x]  = 2*Ny+Nx+1:2*Ny+2*Nx
    VarId[:η]  = 2*Ny+2*Nx+1:2*Ny+2*Nx+nfa
    ωi  = 2*Ny+2*Nx+nfa+1

    Ns,Nc = nf+1,nfa
    """
    Done
    1. removed first equation of histogram
    Must do
    2. remove an equation from EE
    3. remove 1st variable from θ
    4. remove first variable from λ
    """
    Fxp = jac[:,VarId[:xp]][1:end,1:end] # removed last eqt of EE, and 1st variable in λ 
    Fyp = jac[:,VarId[:yp]][1:end,1:end] 
    Fx = jac[:,VarId[:x]][1:end,1:end]
    Fy = jac[:,VarId[:y]][1:end,1:end]
    Fη = jac[:,VarId[:η]][1:end,1:end]
    Fϵ = jac[:,ωi][1:end,1:end]
    Γ0 = -[Fxp Fyp]
    Γ1 = [Fx Fy]
    Ψ = Fϵ
    Π = Fη
    C = fill(0.0,size(Ψ))
    @show size(Γ0)
    @show size(Γ1)
    @show size(Ψ)
    @show size(Π)
    @show size(C)
    Phi1,cons,B1,fmat,fwt,ywt,_,eu1,_ =  gensysdt(Γ0, Γ1, C , Ψ , Π, 1.0 + 1e-10)

    return Phi1,cons,B1,fmat,fwt,ywt,eu1 
end



#function simulation(timePeriods
A,cons,B,fmat,fwt,ywt,eu1 = RationalExpectations(θeq,disteq,lpol,RM)



using QuantEcon

simul_length = 200
na = RM.Collocation.na
nx = RM.Distribution.DistributionSize
ns = RM.MarkovChain.ns
nf = nx*ns
nfa = na*ns
disGrid = RM.Distribution.DistributionAssetGrid
H = eye(size(A,1))
lss = LSS(A,B,H)

X_simul, _ = simulate(lss, simul_length);
xss = [disteq;0.0;θeq]
X_simul = X_simul + repmat(xss,1,simul_length)


pol = fill(0.0,(na,ns,simul_length))
dis = fill(0.0,(nx,ns,simul_length))
Kt = fill(0.0,(simul_length,))
Shockst = fill(0.0,(simul_length,))
constrainedt = fill(0.0,(simul_length,2))
for i = 1:simul_length
    pol[:,:,i] = reshape(X_simul[nf+2:nf+1+nfa,i],na,ns)
    dis[:,:,i] = reshape(X_simul[1:nf,i],nx,ns)
    Kt[i] = dot(disGrid,dis[:,1,i]) + dot(disGrid,dis[:,2,i])
    Shockst[i] = X_simul[nf+1,i]
    constrainedt[i,1] = dis[1,1,i]/sum(dis[:,1,i])
    constrainedt[i,2] = dis[1,2,i]/sum(dis[:,2,i])
end

p1 = plot(constrainedt[:,1]+constrainedt[:,2], title = "Borrowing constrained")
p2 = plot(Kt, title = "aggregate capital")
p3 = plot(Shockst, title = "Aggregate shocks")
p4 = plot(disGrid,dis[:,:,1],title="Steady state distribution",xlims = (0.0,10))
p = plot(p1,p2,p3,p4, layout = (2,2), legend=false, size = (1000,400))
savefig(p,"timeseries.pdf")


mini = argmin(Shockst) ## smallest aggregate shock
maxi = argmax(Shockst) ## largest aggregate shock
p1 = plot(disGrid,dis[:,1,mini],label=string("exp(z)= ",round(exp(Shockst[mini]),3)))
p1 = plot!(disGrid,dis[:,1,maxi],label=string("exp(z)= ",round(exp(Shockst[maxi]),3)))
p2 = plot(disGrid,dis[:,2,mini],label=string("exp(z)= ",round(exp(Shockst[mini]),3)))
p2 = plot!(disGrid,dis[:,2,maxi],label=string("exp(z)= ",round(exp(Shockst[maxi]),3)))
p = plot(p1,p2,layout=(1,2), size=(800,400),title="Distribution of Assets Across Aggregate States")
p = plot!(titlefont=("Helvetica",8))
p = plot!(legendfont=("Helvetica",6),xlims=(0.0,15.0))
savefig(p,"enddistribution.pdf")








