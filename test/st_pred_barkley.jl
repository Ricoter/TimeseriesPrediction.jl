using TimeseriesPrediction
import Statistics: mean
using Test

include("system_defs.jl")

@testset "Barkley STTS" begin
    Nx = 50
    Ny = 50
    Tskip = 200
    Ttrain = 400
    p = 20
    T = Tskip + Ttrain + p
    U, V = barkley_const_boundary(T, Nx, Ny)


    τ = 1
    k = 1
    c = 20

    @testset "V, D=$D, B=$B" for D=2, B=1
        Vtrain = V[Tskip + 1:Tskip + Ttrain]
        Vtest  = V[Tskip + Ttrain :  T]
        em = STDelayEmbedding(Vtrain,D,τ,B,k,c)
        Vpred = localmodel_stts(Vtrain,em,p).spred
        @test Vpred[1] == Vtrain[end]
        err = [abs.(Vtest[i]-Vpred[i]) for i=1:p+1]
        for i in 1:p
            @test maximum(err[i]) < 0.1
        end
    end
    @testset "U, D=2, B=1" begin
        D=2; B=1
        Utrain = U[Tskip + 1:Tskip + Ttrain]
        Utest  = U[Tskip + Ttrain :  T]
        em = STDelayEmbedding(Utrain,D,τ,B,k,c)
        Upred = localmodel_stts(Utrain,em,p).spred
        @test Upred[1] == Utrain[end]
        err = [abs.(Utest[i]-Upred[i]) for i=1:p+1]
        for i in 1:p
            @test maximum(err[i]) < 0.2
        end
    end
    @testset "crosspred V → U" begin
        D = 2; B = 2
        Utrain = U[Tskip + 1:Tskip + Ttrain]
        Vtrain = V[Tskip + 1:Tskip + Ttrain]
        Utest  = U[Tskip + Ttrain - (D-1)τ + 1:  T]
        Vtest  = V[Tskip + Ttrain - (D-1)τ + 1:  T]
        em = STDelayEmbedding(Vtrain, D,τ,B,k,c)
        R = reconstruct(Vtrain, em)
        tree = KDTree(R[:,1:end-2500])
        Upred = crosspred_stts(Utrain,Vtest, em, R, tree).pred_out
        err = [abs.(Utest[1+(D-1)τ:end][i]-Upred[i]) for i=1:p-1]
        for i in 1:length(err)
            #@test maximum(err[i]) < 0.2 #difficult errors have peaks especially with
            #short training
            @test mean(err[i]) < 0.1
        end
    end

    @testset "Periodic, D=$D, B=$B" for D=2:3, B=1:2
        U,V = barkley_periodic_boundary(T, Nx, Ny)
        c = false
        Vtrain = V[Tskip + 1:Tskip + Ttrain]
        Vtest  = V[Tskip + Ttrain :  T]
        em = STDelayEmbedding(Vtrain, D,τ,B,k,c)
        Vpred = localmodel_stts(Vtrain, em, p).spred
        @test Vpred[1] == Vtrain[end]
        err = [abs.(Vtest[i]-Vpred[i]) for i=1:p+1]
        for i in 1:p
            @test maximum(err[i]) < 0.1
        end
    end

    @testset "Periodic diff. inital, D=$D, B=$B" for D=2:3, B=2
        Ttrain = 500
        T = Tskip + Ttrain + p
        U,V = barkley_periodic_boundary_nonlin(T, Nx, Ny)
        c = false
        Vtrain = V[Tskip + 1:Tskip + Ttrain]
        Vtest  = V[Tskip + Ttrain :  T]
        em = STDelayEmbedding(Vtrain, D,τ,B,k,c)
        Vpred = localmodel_stts(Vtrain, em, p).spred
        @test Vpred[1] == Vtrain[end]
        err = [abs.(Vtest[i]-Vpred[i]) for i=1:p+1]
        for i in 1:p
            @test maximum(err[i]) < 0.1
        end
    end
end
