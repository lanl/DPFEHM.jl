using Test
import DifferentiableBackwardEuler
import DPFEHM

doplot = false
if doplot == true
	import PyPlot
end

#Theis solution
function W(u)
	if u <= 1
		return -log(u) + -0.57721566 + 0.99999193u^1 + -0.24991055u^2 + 0.05519968u^3 + -0.00976004u^4 + 0.00107857u^5
	else
		return (u^2 + 2.334733u + 0.250621) / (u^2 + 3.330657u + 1.681534) * exp(-u) / u
	end
end
function theis(t, r, T, S, Q)
	return Q * W(r^2 * S / (4 * T * t)) / (4 * pi * T)
end

#test Theis solution against groundwater model
steadyhead = 1e3
sidelength = 50.0
thickness = 10.0
n = 101
ns = [n, n]
coords, neighbors, areasoverlengths, volumes = DPFEHM.regulargrid2d([-sidelength, -sidelength], [sidelength, sidelength], ns, thickness)
k = 1e-5
Ks = fill(k, length(neighbors))
Q = 1e-3
Ss = 0.1
specificstorage = fill(Ss, size(coords, 2))
S = Ss * thickness
hycos = fill(k, length(areasoverlengths))
Qs = zeros(size(coords, 2))
Qs[ns[2] * (div(ns[1] + 1, 2) - 1) + div(ns[2] + 1, 2)] = -Q#put a fluid source in the middle
dirichletnodes = Int[]
dirichleths = zeros(size(coords, 2))
for i = 1:size(coords, 2)
	if abs(coords[1, i]) == sidelength || abs(coords[2, i]) == sidelength
		push!(dirichletnodes, i)
		dirichleths[i] = steadyhead
	end
end
function unpack(p)
	@assert length(p) == length(neighbors)
	Ks = p[1:length(neighbors)]
	return Ks
end
function f_gw(u, p, t)
	Ks = unpack(p)
	return DPFEHM.groundwater_residuals(u, Ks, neighbors, areasoverlengths, dirichletnodes, dirichleths, Qs, specificstorage, volumes)
end
function f_gw_u(u, p, t)
	Ks = unpack(p)
	return DPFEHM.groundwater_h(u, Ks, neighbors, areasoverlengths, dirichletnodes, dirichleths, Qs, specificstorage, volumes)
end
function f_gw_p(u, p, t)
	Ks = unpack(p)
	return DPFEHM.groundwater_Ks(u, Ks, neighbors, areasoverlengths, dirichletnodes, dirichleths, Qs, specificstorage, volumes)
end
f_gw_t(u, p, t) = zeros(length(u))
t0 = 0.0
tfinal = 60 * 60 * 24 * 1e1
h0 = fill(steadyhead, size(coords, 2))
p = Ks
@time h_gw = DifferentiableBackwardEuler.steps_diffeq(h0, f_gw, f_gw_u, f_gw_p, f_gw_t, p, t0, tfinal; abstol=1e-6, reltol=1e-6)
r0 = 0.1
goodnodes = collect(filter(i->coords[2, i] == 0 && coords[1, i] > r0 && coords[1, i] <= sidelength / 2, 1:size(coords, 2)))
rs = coords[1, goodnodes]
T = thickness * k
theis_drawdowns = theis.(h_gw.t[end], rs, T, S, Q)
gw_drawdowns = -h_gw[end][goodnodes] .+ steadyhead
if doplot
	fig, ax = PyPlot.subplots()
	ax.plot(rs, theis_drawdowns, "r.", ms=20, label="Theis")
	ax.plot(rs, gw_drawdowns, "k", linewidth=3, label="DPFEHM groundwater")
	ax.set_xlabel("x [m]")
	ax.set_ylabel("drawdown [m]")
	ax.legend()
	display(fig)
	println()
	PyPlot.close(fig)
end
@test isapprox(theis_drawdowns, gw_drawdowns; atol=1e-1)

#test Theis solution against richards equation model
coords_richards = vcat(coords, zeros(size(coords, 2))')
alphas = fill(0.5, length(neighbors))
Ns = fill(1.25, length(neighbors))
function f_richards(u, p, t)
	Ks = unpack(p)
	return DPFEHM.richards_residuals(u, Ks, neighbors, areasoverlengths, dirichletnodes, dirichleths, coords_richards, alphas, Ns, Qs, specificstorage, volumes)
end
function f_richards_u(u, p, t)
	Ks = unpack(p)
	return DPFEHM.richards_psi(u, Ks, neighbors, areasoverlengths, dirichletnodes, dirichleths, coords_richards, alphas, Ns, Qs, specificstorage, volumes)
end
function f_richards_p(u, p, t)
	Ks = unpack(p)
	return DPFEHM.richards_Ks(u, Ks, neighbors, areasoverlengths, dirichletnodes, dirichleths, coords_richards, alphas, Ns, Qs, specificstorage, volumes)
end
f_richards_t(u, p, t) = zeros(length(u))
@time h_richards = DifferentiableBackwardEuler.steps_diffeq(h0, f_richards, f_richards_u, f_richards_p, f_richards_t, p, t0, tfinal; abstol=1e-6, reltol=1e-6)
richards_drawdowns = -h_richards[end][goodnodes] .+ steadyhead
if doplot
	fig, ax = PyPlot.subplots()
	ax.plot(rs, theis_drawdowns, "r.", ms=20, label="Theis")
	ax.plot(rs, richards_drawdowns, "k", linewidth=3, label="DPFEHM richards")
	ax.set_xlabel("x [m]")
	ax.set_ylabel("drawdown [m]")
	ax.legend()
	display(fig)
	println()
	PyPlot.close(fig)
end
@test isapprox(theis_drawdowns, richards_drawdowns; atol=1e-1)
@test isapprox(h_richards[:, :], h_gw[:, :])#make sure richards and groundwater are giving the same thing