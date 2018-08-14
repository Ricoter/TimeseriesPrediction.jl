using Statistics
using LinearAlgebra
export STDelayEmbedding, PCAEmbedding, reconstruct
export PeriodicBoundary,ConstantBoundary

abstract type AbstractBoundaryCondition end
struct ConstantBoundary{C} <: AbstractBoundaryCondition end
struct PeriodicBoundary    <: AbstractBoundaryCondition end

abstract type AbstractSpatialEmbedding{T,Φ,BC,X} <: AbstractEmbedding end


struct Region{Φ}
	mini::NTuple{Φ,Int64}
	maxi::NTuple{Φ,Int64}
end

Base.length(r::Region{Φ}) where Φ = prod(r.maxi .- r.mini .+1)
Base.in(idx, r::Region{Φ}) where Φ = begin
	for φ=1:Φ
		r.mini[φ] <= idx[φ] <= r.maxi[φ] || return false
 	end
 	return true
end
Base.CartesianIndices(r::Region{Φ}) where Φ =
	 CartesianIndices{Φ,NTuple{Φ,UnitRange{Int64}}}(
	 ([r.mini[φ]:r.maxi[φ] for φ=1:Φ]...,))


function inner_region(βs::Vector{CartesianIndex{Φ}}, fsize) where Φ
	mini = Int[]
	maxi = Int[]
	for φ = 1:Φ
		js = map(β -> β[φ], βs) # jth entries
		mi,ma = extrema(js)
		push!(mini, 1 - min(mi, 0))
		push!(maxi,fsize[φ] - max(ma, 0))
	end
	return Region{Φ}((mini...,), (maxi...,))
end

#TODO: Not pretty, not good, make better
function project_inside(α::CartesianIndex{Φ}, r::Region{Φ}) where Φ
	CartesianIndex(mod.(α.I .-1, r.maxi).+1)
end


struct STDelayEmbedding{T,Φ,BC,X} <: AbstractSpatialEmbedding{T,Φ,BC,X}
  	τ::Vector{Int64}
	β::Vector{CartesianIndex{Φ}}
	inner::Region{Φ}  #inner field far from boundary
	whole::Region{Φ}	#whole field

	#Additional fields for values that are needed VERY often like millions of times
	τmax::Int64  	# maximum(τ)
	num_pt::Int64   #  number of points in space

	function STDelayEmbedding{T,Φ,BC,X}(τ,β,fsize) where {T,Φ,BC,X}
		inner = inner_region(β, fsize)
		whole = Region((ones(Int,Φ)...,), fsize)
		τmax  = maximum(τ)
		num_pt= prod(fsize)
		return new{T,Φ,BC,X}(τ,β,inner,whole, τmax, num_pt)
	end
end

function STDelayEmbedding(
		s::AbstractArray{<:AbstractArray{T,Φ}},
		D, τ, B, k, ::Type{BC}
		) where {T,Φ, BC<:AbstractBoundaryCondition}

	X = (D+1)*(2B+1)^Φ
	τs = Vector{Int64}(undef,X)
	βs = Vector{CartesianIndex{Φ}}(undef,X)
	n = 1
	for d=0:D, α = Iterators.product([-B*k:k:B*k for φ=1:Φ]...)
		τs[n] = d*τ
		βs[n] = CartesianIndex(α)
		n +=1
	end
	return STDelayEmbedding{T,Φ,BC, X}(τs, βs, size(s[1]))
end


function Base.summary(::IO, ::STDelayEmbedding{T,Φ,BC, X}) where {T,Φ,BC,X}
	println("$(Φ)D Spatio-Temporal Delay Embedding with $X Entries")
end

#This function is not safe. If you call it directly with bad params - can fail
function (r::STDelayEmbedding{T,Φ,ConstantBoundary{C},X})(rvec,s,t,α) where {T,Φ,C,X}
	if α in r.inner
		@inbounds for n=1:X
			rvec[n] = s[ t + r.τ[n] ][ α + r.β[n] ]
		end
	else
		@inbounds for n=1:X
			rvec[n] = 	if α + r.β[n] in r.whole
							s[ t + r.τ[n] ][ α + r.β[n] ]
						else
							C
						end
		end
	end
	return nothing
end

function (r::STDelayEmbedding{T,Φ,PeriodicBoundary,X})(rvec,s,t,α) where {T,Φ,X}
	if α in r.inner
		@inbounds for n=1:X
			rvec[n] = s[ t + r.τ[n] ][ α + r.β[n] ]
		end
	else
		@inbounds for n=1:X
			rvec[n] = s[ t + r.τ[n] ][ project_inside(α + r.β[n], r.whole) ]
		end
	end
	return nothing
end



get_num_pt(em::STDelayEmbedding) = em.num_pt
get_τmax(em::STDelayEmbedding) = em.τmax
outdim(em::STDelayEmbedding{T,Φ,BC,X}) where {T,Φ,BC,X} = X


function reconstruct(s::AbstractArray{<:AbstractArray{T,Φ}},
	em::AbstractSpatialEmbedding{T,Φ,BC,X}
	) where {T<:Number,Φ,BC,X}
	timesteps = (length(s) - get_τmax(em))
	num_pt    = get_num_pt(em)
	L         = timesteps*num_pt


	pt_in_space = CartesianIndices(s[1])
	lin_idxs    = LinearIndices(s[1])
	data = Matrix{T}(undef,X,L)
	recv = zeros(T,X)
	@inbounds for t in 1:timesteps, α in pt_in_space
		n = (t-1)*num_pt+lin_idxs[α]
		#Maybe unsafe array views here
		#recv = view(data,:,n)
		em(recv,s,t,α)
		#very odd. data[:,n] .= recv allocates
		for i=1:X data[i,n] = recv[i] end
	end
	return data
end
