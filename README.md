# Learning Quantum States with Neural Networks

![Energies_A](data/energies_A.png)
Figure 1: Statistical expectation of the energy and standard error of the mean for the anti-ferromagnetic Ising chain of $n = 1024$ spins with $J = -0.5$ and $B = 0.1$.

![Correlations_A](data/correlations_A.png)
Figure 2: Correlations for the anti-ferromagnetic Ising chain of $n = 1024$ spins with $J = -0.5$ and $B = 0.1$.
## Contents

1. [Introduction](#introduction)
2. [Restricted Boltzmann Machines](#restricted-boltzmann-machines)
3. [Neural Network Quantum States](#neural-network-quantum-states)
4. [Transverse Field Ising Model](#transverse-field-ising-model)
5. [Stochastic Optimization](#stochastic-optimization)
6. [Derivation of Optimization Algorithm](#derivation-of-optimization-algorithm)
7. [Fortran Implementation](#fortran-implementation)
8. [Building with fpm](#building-with-fpm)

## Introduction

Quantum mechanics emerges from classical mechanics by the relaxation of commutativity among the observables as assumed by classical probability theory. The most striking consequence of this relaxation is the insufficiency of real-valued probability distributions to encode the interference phenomena observed by experiment. In response, we generalize the notion of probability distributions from real-valued distributions over the set of possible outcomes which combine convexly, to complex-valued distributions over the set of possible outcomes which combine linearly. The complex-valued probabilities are able to encode the observed interference patterns in their relative phases. Such quantum probability distributions describe our knowledge of possible outcomes of measurements on systems which cannot be said to be in a definite state prior to measurement.

The increase in predictive power offered by quantum mechanics came with the price of computational difficulties. Unlike the classical world, whose dimensionality scales additively with the number of subsystems, the dimensionality scaling of quantum systems is multiplicative. Thus, even small systems quickly become intractable without approximation techniques. Luckily, it is rarely the case that knowledge of the full state space is required to accurately model a given system, as most information may be contained in a relatively small subspace. Many of the most successful approximation techniques of the last century, such as Born–Oppenheimer and variational techniques like Density Functional Theory, rely on this convenient notion for their success. With the rapid development of machine learning, a field which specializes in dimensionality reduction and feature extraction of very large datasets, it is natural to apply these novel techniques for dealing with the canonical large data problem of the physical sciences.

## Restricted Boltzmann Machines

The Universal Approximation Theorems are a collection of results concerning the ability of artificial neural networks to arbitrarily approximate different classes of functions. In particular, the Restricted Boltzmann Machine (RBM) is a shallow two-layer network consisting of $n$ input nodes or *visible units*, and $m$ output nodes or *hidden units* such that each input $v \in \\{0,1\\}^n$ and output $h \in \\{0,1\\}^m$ are Boolean vectors of respective length. Letting $\mathcal{M}$ be a parameter manifold with points $\alpha \in \mathcal{M}$, the RBM is characterized by such parameters $\alpha = \\{a,b,w\\}$ where $a \in \mathbb{R}^n$ are the visible layer biases, $b \in \mathbb{R}^m$ are the hidden layer biases, and $w \in \mathbb{R}^{m \times n}$ are the weights which fully connect the layers. The network is "restricted" in the sense that there are no intra-layers connections.

Let $V = \\{0,1\\}^n$ be the set of inputs, let $H = \\{0,1\\}^m$ be the set of outputs, and let $X = V \times H$ be the set of pairs. Then the RBM is a universal approximator of Boltzmann probability distributions $p(\alpha):X \to [0,1]$ at each $\alpha \in \mathcal{M}$ defined by
    $$X \ni (v,h) \mapsto p(v,h,\alpha) = \frac{\exp[-E(v,h,\alpha)]}{Z(\alpha)} = \frac{\exp(a^\perp v + b^\perp h + h^\perp wv)}{\sum_{(v',h') \in X} \exp(a^\perp v' + b^\perp h' + {h'}^\perp wv')} \in [0,1]$$
where $E(v,h,\alpha) = -a^\perp v - b^\perp h - h^\perp wv$ is the parametrized Boltzmann energy and $Z(\alpha) = \sum_{(v',h') \in X} \exp(a^\perp v' + b^\perp h' + {h'}^\perp wv')$ is the partition function which normalizes the probabilities, with $\perp$ denoting the matrix transpose. From the joint probability distribution $p(\alpha)$, we may construct the marginal distributions as the restrictions $p_V(\alpha):V \to [0,1]$ and $p_H(\alpha): H \to [0,1]$ at each $\alpha \in \mathcal{M}$, given by the partial sums
    $$p_V(v,\alpha) = \sum_{h \in H} p(v,h,\alpha)\~\~,\~\~p_H(h,\alpha) = \sum_{v \in V} p(v,h,\alpha)$$
over $H$ and $V$ respectively. Due to the restricted nature of the RBM, the activation probabilities $p(h_i=1|v,\alpha)$ and $p(v_j=1|h,\alpha)$ of each layer are mutually exclusive for all $i \in [1,m]$ and $j \in [1,n]$ such that the conditional probabilities are the products
    $$p(h|v,\alpha) = \prod_{i=1}^m p(h_i=1|v,\alpha)~~,~~p(v|h,\alpha) = \prod_{j=1}^n p(v_j=1|h,\alpha)$$
of activation probabilities. The traditional method for training an RBM involves [Hinton](https://en.wikipedia.org/wiki/Geoffrey_Hinton)'s Contrastive Divergence technique, which will not be covered here.

## Neural Network Quantum States

The RBM is a natural choice for representing wave-functions of systems of spin $\frac{1}{2}$ fermions where each input vector represents a configuration of $n$ spins. Ultimately, we seek to solve the time-independent Schrödinger equation $H\ket{\psi_0} = E_0\ket{\psi_0}$ for the ground state $\ket{\psi_0}$ and its corresponding energy $E_0$ for a given system having Hamiltonian $H$. We take a variational approach by proposing a parametrized trial state as a vector-valued mapping $\ket{\psi}:\mathcal{M} \to \mathcal{H}$ on a low-dimensional parameter manifold $\mathcal{M}$ of points $\alpha \in \mathcal{M}$ to a $2^n$-dimensional state space $\mathcal{H}$ and propose infinitesimal variations to $\alpha \in \mathcal{M}$ until $\ket{\psi(\alpha)} \approx \ket{\psi_0}$.

Letting $S = \\{0,1\\}^n$ be the set of inputs of the RBM, we may choose an orthonormal basis $\\{\ket{s}\\} \subset \mathcal{H}$ labeled by the configurations $s \in S$ such that the trial state at $\alpha \in \mathcal{M}$ is a linear combination $\ket{\psi(\alpha)} = \sum_{s \in S} \psi(s,\alpha) \ket{s} \in \mathcal{H}$, where the components $\psi(s,\alpha) \in \mathbb{C}$ are wave-functions of the configurations $s \in S$ at each $\alpha \in \mathcal{M}$.

The trial state wave-functions $\psi(\alpha):S \to \mathbb{C}$ are represented as a Restricted Boltzmann Machine with complex parameters $\alpha = \\{a,b,w\\}$, constructed as the marginal distribution on the inputs of the RBM. With inputs $S = \\{0,1\\}^n$ and outputs $H = \\{0,1\\}^m$, the RBM with complex parameters is a universal approximator of complex probability distributions $\Psi(\alpha):S \times H \to \mathbb{C}$ at each $\alpha \in \mathcal{M}$ such that the trial state wave-functions $\psi(\alpha):S \to \mathbb{C}$ at each $\alpha \in \mathcal{M}$ are the marginal distribution defined by
    $$S \ni s \mapsto \psi(s,\alpha) = \sum_{h \in H} \Psi(s,h,\alpha) = \sum_{h \in H} \exp(a^\dagger s + b^\dagger h + h^\dagger ws) = \exp(a^\dagger s) \sum_{h \in H} \exp(b^\dagger h + h^\dagger ws) = \exp\bigg(\sum_{j=1}^n a_j^\*s_j\bigg) \sum_{h \in H} \exp\bigg(\sum_{i=1}^m b_i^\*h_i + \sum_{i=1}^m h_i \sum_{j=1}^n w_{ij} s_j\bigg) = \exp\bigg(\sum_{j=1}^n a_j^\*s_j\bigg) \sum_{h \in H} \prod_{i=1}^m \exp\bigg(b_i^\*h_i + h_i \sum_{j=1}^n w_{ij} s_j\bigg) = \exp\bigg(\sum_{j=1}^n a_j^\* s_j\bigg) \prod_{i=1}^m \sum_{h_i=0}^1 \exp\bigg(b_i^\*h_i + h_i \sum_{j=1}^n w_{ij} s_j\bigg) = \exp\bigg(\sum_{j=1}^n a_j^\* s_j\bigg) \prod_{i=1}^m \bigg[ 1 + \exp\bigg(b_i^\* + \sum_{j=1}^n w_{ij} s_j\bigg)\bigg] \in \mathbb{C}$$
where we ignore the normalization factor of the wave-function, and where $\dagger$ represents the matrix conjugate transpose. By the Born rule, the real, normalized probability distribution $p(\alpha):S \to [0,1]$ associated to the wave-function $\psi(\alpha)$ at each $\alpha \in \mathcal{M}$ is defined by $S \ni s \mapsto p(s,\alpha) = |\psi(s,\alpha)|^2/\sum_{s' \in S} |\psi(s',\alpha)|^2 \in [0,1]$.

The variational energy functional $E[\psi(\alpha)]$ associated to the variational state $\ket{\psi(\alpha)}$ at each $\alpha \in \mathcal{M}$ is the statistical expectation $E[\psi(\alpha)] = \langle H \rangle_{\psi(\alpha)}$ of the Hamiltonian $H$ in the state $\ket{\psi(\alpha)}$, given by
    $$E[\psi(\alpha)] = \frac{\langle \psi(\alpha), H\psi(\alpha) \rangle}{\langle \psi(\alpha), \psi(\alpha) \rangle} = \frac{\sum_{s,s' \in S} \psi^\* (s,\alpha) H_{ss'} \psi(s',\alpha)}{\sum_{s' \in S} |\psi(s',\alpha)|^2} = \frac{\sum_{s \in S} |\psi(s,\alpha)|^2 \left(\sum_{s' \in S} H_{ss'} \frac{\psi(s',\alpha)}{\psi(s,\alpha)}\right)}{\sum_{s' \in S} |\psi(s',\alpha)|^2} = \sum_{s \in S} p(s,\alpha) E_{\text{loc}}(s,\alpha)$$
where we define the variational local energies $E_{\text{loc}}(s,\alpha) = \sum_{s' \in S} H_{ss'} \frac{\psi(s',\alpha)}{\psi(s,\alpha)}$, with $H_{ss'}$ being the matrix element of $H$ in between the states $\ket{s}$ and $\ket{s'}$. Thus $E[\psi(\alpha)] = \sum_{s \in S} p(s,\alpha) E_{\text{loc}}(s,\alpha)$ is the statistical expectation of the local energies weighted by the real probability distribution $p(\alpha):S \to [0,1]$.

## Transverse Field Ising Model

In this demonstration, we assume the prototypical Ising spin model for a one-dimensional lattice of spin $\frac{1}{2}$ particles, whose Hamiltonian is a $2^n \times 2^n$ matrix given by
    $$H = -J \sum_{j=1}^{n-1} \sigma_z^{(j)} \sigma_z^{(j+1)} - B \sum_{j=1}^n \sigma_x^{(j)}$$
where we use the shorthand notation $\sigma_z^{(j)} \sigma_z^{(j+1)} = I^{(1)} \otimes \cdots \otimes \sigma_z^{(j)} \otimes \sigma_z^{(j+1)} \otimes \cdots \otimes I^{(n)}$ to denote the tensor product of the $2 \times 2$ identity matrix with the Pauli matrix $\sigma_z$ located at positions $j$ and $j+1$, and where $\sigma_x^{(j)} = I^{(1)} \otimes \cdots \otimes \sigma_x^{(j)} \otimes \cdots \otimes I^{(n)}$ denotes $\sigma_x$ at position $j$. The constant $J$ represents the nearest neighbor coupling strength, and $B$ represents the strength of the transverse field restricted to $|B| < 1$ to correspond to the ordered phase of the Ising material. When $J>0$, nearest neighbors tend to align parallel (ferromagnetic), and tend to align anti-parallel when $J<0$ (anti-ferromagnetic). The local energy of a configuration $s \in S$ in the Ising model can be seen to be
    $$E_{\text{loc}}(s,\alpha) =-J \sum_{j=1}^{n-1} \sigma_j \sigma_{j+1} - B \sum_{s' \in S_f} \frac{\psi(s',\alpha)}{\psi(s,\alpha)}$$
where $\sigma_j = -2s_j + 1 \in \\{1,-1\\}$ and $S_f$ consists of $n$ configurations in which each respective spin in the configuration $s$ has been inverted.

## Stochastic Optimization

Evaluating the energy functional $E[\psi(\alpha)] = \sum_{s \in S} p(s,\alpha) E_{\text{loc}}(s,\alpha)$ at each $\alpha \in \mathcal{M}$ involves an explicit calculation of the distribution $p(\alpha):S \to [0,1]$ for each $s \in S$ and a sum over $2^n$ states. Using Monte Carlo methods, we may draw $N$ possibly overlapping samples $\tilde{S}$ from $S$ according to the distribution $p(\alpha)$ such that the drawn samples $\tilde{S}$ are represented in proportion to their contribution to $p(\alpha)$. In other words, the samples drawn will tend to be from regions of $S$ associated with the highest probabilities and which therefore contribute the most to $E[\psi(\alpha)]$. We may then make the reasonable approximation
    $$E[\psi(\alpha)] \approx \frac{1}{N} \sum_{s \in \tilde{S}} E_{\text{loc}}(s,\alpha)$$
of the energy functional as a simple average of the local energies over the drawn samples $\tilde{S}$ weighted by equal probabilities $1/N$. The samples can be drawn using the well-known Metropolis-Hastings algorithm, a Markov Chain Monte Carlo algorithm of the following form:

```fortran
SUBROUTINE metropolis_hastings:
    markov_chain(1) ← random_sample(n)
    FOR i ∈ [2,N] DO
        s ← markov_chain(i-1)
        rind ← random_index(lo=1, hi=n)
        s_prop ← invert_spin(config=s, at=rind)
        IF r_unif(0,1) < |ψ(s_prop)/ψ(s)|^2 THEN
            markov_chain(i) ← s_prop
        ELSE
            markov_chain(i) ← s
        END IF
    END FOR
    RETURN markov_chain
END SUBROUTINE metropolis_hastings
```

In practice, we allow for a thermalization period, or "burn-in" period, during which the sampling process moves the initial random sample into the stationary distribution before we can begin recording samples. As we can see, the acceptance probabilities in the Metropolis-Hastings algorithm and the form of the local energy involve only ratios of the wave-functions $\psi(s,\alpha)$ for different configurations, and therefore we are justified in ignoring the normalization factor in our derivation of $\psi(s,\alpha)$. Once all samples are drawn, we may estimate the energy functional as an average of the local energies over the drawn samples.

The stochastic optimization algorithm is a first order optimization that involves infinitesimal variations to the parameters $\alpha \in \mathcal{M}$ according to the update rule
    $$\alpha \leftarrow \alpha + \delta\alpha$$
where the variation $\delta\alpha$ is in the direction opposite the generalized forces $F(\alpha)$ having components
    $$F_l(\alpha) = \langle \partial_l^\dagger H \rangle_{\psi(\alpha)} - \langle \partial_l^\dagger \rangle_{\psi(\alpha)} \langle H \rangle_{\psi(\alpha)} = \frac{\langle \partial_l \psi(\alpha), H \psi(\alpha) \rangle}{\langle \psi(\alpha), \psi(\alpha) \rangle} - \frac{\langle \partial_l \psi(\alpha), \psi(\alpha) \rangle}{\langle \psi(\alpha), \psi(\alpha) \rangle} \frac{\langle \psi(\alpha), H \psi(\alpha) \rangle}{\langle \psi(\alpha), \psi(\alpha) \rangle} = \sum_{s \in S} p(s,\alpha) O_l^\*(s,\alpha) E_{\text{loc}}(s, \alpha) - \bigg[ \sum_{s \in S} p(s,\alpha) O_l^\*(s,\alpha) \bigg] \bigg[ \sum_{s \in S} p(s,\alpha) E_{\text{loc}}(s,\alpha) \bigg] \approx \frac{1}{N} \sum_{s \in \tilde{S}} O_l^\*(s,\alpha) E_{\text{loc}}(s, \alpha) - \bigg[ \frac{1}{N} \sum_{s \in \tilde{S}} O_l^\*(s,\alpha) \bigg] \bigg[ \frac{1}{N} \sum_{s \in \tilde{S}} E_{\text{loc}}(s, \alpha) \bigg]$$
where we define the logarithmic derivatives
    $$O_l(s,\alpha) = \frac{\partial}{\partial \alpha_l} \ln \psi(s, \alpha) = \frac{1}{\psi(s, \alpha)} \frac{\partial}{\partial \alpha_l} \psi(s, \alpha)$$
of the variational wave-functions $\psi(s, \alpha)$ in terms of diagonal operators $O_l$ given by $O_l \psi(s, \alpha) = O_l(s,\alpha)$. In statistical terms, the forces $F_l$ are the expected values of the product of deviation operators $\Delta \partial_l^\dagger = \partial_l^\dagger - \langle \partial_l^\dagger \rangle_{\psi(\alpha)}$ and $\Delta H = H - \langle H \rangle_{\psi(\alpha)}$ in the variational state $\ket{\psi(\alpha)}$. i.e.
    $$F_l(\alpha) = \langle \Delta \partial_l^\dagger \Delta H \rangle_{\psi(\alpha)} = \langle \partial_l^\dagger H - \langle \partial_l^\dagger \rangle_{\psi(\alpha)} H - \partial_l^\dagger \langle H \rangle_{\psi(\alpha)} + \langle \partial_l^\dagger \rangle_{\psi(\alpha)} \langle H \rangle_{\psi(\alpha)} \rangle_{\psi(\alpha)} = \langle \partial_l^\dagger H \rangle_{\psi(\alpha)} - \langle \partial_l^\dagger \rangle_{\psi(\alpha)} \langle H \rangle_{\psi(\alpha)}$$
as a correlation function. We then  pre-condition the forces $F(\alpha)$ with a Hermitian positive-definite matrix $S^{-1}(\alpha)$ prior to updating the parameters $\alpha \in \mathcal{M}$, such that the update rule is
    $$\alpha \leftarrow \alpha + \delta\alpha = \alpha - \delta\tau S^{-1}(\alpha) F(\alpha)$$
for some small time step $\delta \tau > 0$, where the matrix $S(\alpha)$ is known as the stochastic reconfiguration matrix whose components are the correlation functions
    $$S_{kl}(\alpha) = \langle \Delta \partial_k^\dagger \Delta \partial_l \rangle_{\psi(\alpha)} = \langle \partial_k^\dagger \partial_l \rangle_{\psi(\alpha)} - \langle \partial_k^\dagger \rangle_{\psi(\alpha)} \langle \partial_l \rangle_{\psi(\alpha)} = \frac{\langle \partial_k \psi(\alpha), \partial_l \psi(\alpha) \rangle}{\langle \psi(\alpha), \psi(\alpha) \rangle} - \frac{\langle \partial_k \psi(\alpha), \psi(\alpha) \rangle}{\langle \psi(\alpha), \psi(\alpha) \rangle} \frac{\langle \psi(\alpha), \partial_l \psi(\alpha) \rangle}{\langle \psi(\alpha), \psi(\alpha) \rangle} = \sum_{s \in S} p(s,\alpha) O_k^\*(s,\alpha) O_l(s,\alpha) - \bigg[ \sum_{s \in S} p(s,\alpha) O_k^\*(s,\alpha) \bigg] \bigg[ \sum_{s \in S} p(s,\alpha) O_l(s,\alpha) \bigg] \approx \frac{1}{N} \sum_{s \in \tilde{S}} O_k^\*(s,\alpha) O_l(s,\alpha) - \bigg[ \frac{1}{N} \sum_{s \in \tilde{S}} O_k^\*(s,\alpha) \bigg] \bigg[ \frac{1}{N} \sum_{s \in \tilde{S}} O_l(s,\alpha) \bigg]$$
of the derivative deviations.

## Derivation of Optimization Algorithm

Let $V$ be a neighborhood of a point $\alpha \in \mathcal{M}$ with a local chart of coordinate functions $\alpha_l:\mathcal{M} \to \mathbb{C}$ such that $\alpha_l(\alpha) = 0$ is the origin of the local coordinate system. To derive the stochastic optimization update rule, we first expand the function $\ket{\psi}:\mathcal{M} \to \mathcal{H}$ in a Taylor series
    $$\ket{\psi} = \ket{\psi(\alpha)} + \sum_l \frac{\partial}{\partial \alpha_l} \ket{\psi(\alpha)} \alpha_l + \frac{1}{2} \sum_{kl} \frac{\partial^2}{\partial \alpha_k \partial \alpha_l} \ket{\psi(\alpha)} \alpha_k \alpha_l + \cdots$$
about $\alpha \in \mathcal{M}$. At some nearby point $\alpha + \delta\alpha \in V$, we have
    $$\ket{\psi(\alpha + \delta\alpha)} = \ket{\psi(\alpha)} + \sum_l \delta\alpha_l \frac{\partial}{\partial \alpha_l} \ket{\psi(\alpha)} + \frac{1}{2} \sum_{kl} \delta\alpha_k \delta\alpha_l \frac{\partial^2}{\partial \alpha_k \partial \alpha_l} \ket{\psi(\alpha)} + \cdots \in \mathcal{H}$$
where $\delta\alpha_l \in \mathbb{C}$ is an infinitesimal variation in the $l$-th direction, which is approximated to first order as an affine function
    $$\ket{\psi(\alpha + \delta\alpha)} \approx \ket{\psi(\alpha)} + \sum_l \delta\alpha_l \frac{\partial}{\partial \alpha_l} \ket{\psi(\alpha)} \in \mathcal{H}$$
on $V$. Here, the $\delta\alpha_l$ represent the amount of change to $\alpha$ in each direction needed to linearly approximate the function $\ket{\psi}$ at $\alpha + \delta\alpha \in V$ from the neighboring point $\alpha \in \mathcal{M}$, so that the affine approximation becomes exact in the limit $\delta\alpha_l \to 0$.

Similarly, we define a path $\alpha:[\tau, \tau + \delta \tau] \to \mathcal{M}$ in $\mathcal{M}$ where $\delta\tau > 0$ such that $\alpha(\tau) = \alpha \in \mathcal{M}$ and $\alpha(\tau + \delta \tau) = \alpha + \delta\alpha \in V$, and expand the path about $\tau \in \mathbb{R}$ to see
    $$\alpha(\tau + \delta \tau) = \alpha(\tau) + \delta\tau \frac{d \alpha}{d\tau}(\tau) + \frac{\delta\tau^2}{2} \frac{d^2 \alpha}{d\tau^2}(\tau) + \cdots \approx \alpha(\tau) + \delta\tau \frac{d \alpha}{d\tau}(\tau) \in \mathcal{M}$$
which is an affine function on the closed interval $[\tau, \tau + \delta \tau] \subset \mathbb{R}$. Evaluating $\ket{\psi}:\mathcal{M} \to \mathcal{H}$ at $\alpha(\tau + \delta \tau) \in V$, we find that
    $$\ket{\psi(\alpha(\tau + \delta \tau))} \approx \ket{\psi(\alpha(\tau))} + \delta\tau \frac{d}{d\tau}\ket{\psi(\alpha(\tau))} \in  \mathcal{H}$$
is an affine function on $V$ which becomes exact in the limit $\delta\tau \to 0$. We may compare the first order terms of $\ket{\psi(\alpha(\tau + \delta \tau))}$ and $\ket{\psi(\alpha + \delta\alpha)}$ to find that
    $$\delta \tau \frac{d}{d\tau} \ket{\psi(\alpha(\tau))} = \delta \tau \sum_l \frac{\partial}{\partial \alpha_l} \ket{\psi(\alpha(\tau))} \frac{d \alpha_l}{d\tau}(\tau) = \sum_l \delta\alpha_l(\tau) \frac{\partial}{\partial \alpha_l} \ket{\psi(\alpha(\tau))}$$
is a linear combination of the tangent vectors $\frac{d \alpha_l}{d\tau}(\tau)$ at $\alpha(\tau) \in \mathcal{M}$, so that the total variation $\delta\alpha(\tau) = \delta \tau \frac{d \alpha}{d\tau}(\tau)$ needed to linearly approximate the function $\ket{\psi}$ at $\alpha(\tau + \delta\tau) \in V$ from the neighboring point $\alpha(\tau) \in \mathcal{M}$ at time $\tau$ is in the direction of the tangent vector $\frac{d \alpha}{d\tau}(\tau)$ at $\alpha(\tau) \in \mathcal{M}$ such that
    $$\alpha(\tau + \delta \tau) \approx \alpha(\tau) + \delta\alpha(\tau) = \alpha(\tau) + \delta \tau \frac{d \alpha}{d\tau}(\tau)$$
is the infinitesimal change in the parameters $\alpha(\tau) \in \mathcal{M}$ at time $\tau$ over the interval $[\tau, \tau + \delta \tau]$. Letting $T_\alpha \mathcal{M}$ denote the tangent space of $\mathcal{M}$ at $\alpha(\tau) \in \mathcal{M}$ and $T_{\psi(\alpha)} \mathcal{H}$ denote the tangent space of $\mathcal{H}$ at $\ket{\psi(\alpha(\tau))} \in \mathcal{H}$, we push forward the local vector field $\frac{d \alpha}{d\tau}$ on $V \subset \mathcal{M}$ to the local vector field $\frac{d}{d\tau} \ket{\psi(\alpha)}$ on the image $\tilde{V} = \ket{\psi(V)} \subset \mathcal{H}$ of $V$ under the mapping $\ket{\psi}:\mathcal{M} \to \mathcal{H}$, and note that
    $$\frac{d}{d\tau} \ket{\psi(\alpha(\tau))} \in T_{\psi(\alpha)} \tilde{V}$$
is the pushforward of the tangent vector $\frac{d \alpha}{d\tau}(\tau) \in T_\alpha \mathcal{M}$ at $\alpha(\tau) \in \mathcal{M}$.

By the time-dependent Schrödinger equation, the state $\ket{\psi(\alpha(t))} \in \mathcal{H}$ at some time $t$ will evolve according to $i \frac{d}{dt} \ket{\psi(\alpha(t))} = H \ket{\psi(\alpha(t))}$, which is satisfied (up to a constant) by the propagator $U(t_2 - t_1) = \exp[-i(t_2-t_1)H]$ given the Hamiltonian $H$. Here, the Hamiltonian $H$ is the infinitesimal generator of the one-parameter unitary group of time translations whose elements are the unitary transformations $U(t_2 - t_1):\mathcal{H} \to \mathcal{H}$ on the state space $\mathcal{H}$ for any $t_1, t_2 \in \mathbb{R}$. By performing a Wick rotation $\tau = it$, the state $\ket{\psi(\alpha(\tau))} \in \mathcal{H}$ at some imaginary time $\tau$ will evolve according to the imaginary-time Schrödinger equation $-\frac{d}{d\tau} \ket{\psi(\alpha(\tau))} = H \ket{\psi(\alpha(\tau))}$, which is satisfied (up to a constant) by the non-unitary propagator $U(\tau_2 - \tau_1) = \exp[-(\tau_2-\tau_1)H]$. Taking $\tau_1 = \tau$ and $\tau_2 = \tau + \delta\tau$, we propagate the state $\ket{\psi(\alpha(\tau))} \in \mathcal{H}$ by
    $$\ket{\psi(\alpha(\tau + \delta \tau))} = U(\delta\tau) \ket{\psi(\alpha(\tau))} = \ket{\psi(\alpha(\tau))} - \delta \tau H \ket{\psi(\alpha(\tau))} + \frac{(-\delta\tau)^2}{2}H^2 \ket{\psi(\alpha(\tau))} + \cdots \approx \ket{\psi(\alpha(\tau))} - \delta \tau H \ket{\psi(\alpha(\tau))} \in \mathcal{H}$$
approximated to first order over the interval $[\tau, \tau + \delta \tau]$, which becomes exact in the limit $\delta\tau \to 0$. Enforcing a different normalization for the propagator, we may also evolve the state $\ket{\psi(\alpha(\tau))} \in \mathcal{H}$ according to $- \Delta\frac{d}{d\tau} \ket{\psi(\alpha(\tau))} = \Delta H \ket{\psi(\alpha(\tau))}$ involving the deviations $\Delta \frac{d}{d\tau} = \frac{d}{d\tau} - \left\langle \frac{d}{d\tau} \right\rangle_{\psi(\alpha)}$ and $\Delta H = H - \langle H \rangle_{\psi(\alpha)}$, which is often more advantageous in a stochastic framework.

To determine the actual form of the tangent vector $\frac{d \alpha}{d\tau}(\tau) \in T_\alpha \mathcal{M}$ at time $\tau$, we impose the constraint that the projection
    $$\left\langle \frac{d}{d\tau} \psi(\alpha(\tau)), \bigg[ \Delta \frac{d}{d\tau} + \Delta H \bigg] \psi(\alpha(\tau)) \right\rangle = 0$$
of the state $[ \Delta \frac{d}{d\tau} + \Delta H ] \ket{\psi(\alpha(\tau))} \in T_{\psi(\alpha)} \mathcal{H}$ onto the tangent vector $\frac{d}{d\tau} \ket{\psi(\alpha(\tau))} \in T_{\psi(\alpha)} \tilde{V}$ vanishes, a type of Galerkin condition known as the Dirac-Frenkel-McLachlan variational principle. This condition is motivated by the fact that the subspace $\tilde{V} \subset \mathcal{H}$ is typically of much smaller dimension than $\mathcal{H}$ itself since $\mathcal{M}$ is typically of much smaller dimension than $\mathcal{H}$ as manifolds, resulting in a situation where the tangent vector $\frac{d}{d\tau} \ket{\psi(\alpha(\tau))}  \in T_{\psi(\alpha)} \tilde{V}$ is contained to a low dimensional subspace but $H \ket{\psi(\alpha(\tau))} \in T_{\psi(\alpha)} \mathcal{H}$ is not necessarily contained to this subspace. In order for the imaginary-time Schrödinger equation $-\frac{d}{d\tau} \ket{\psi(\alpha(\tau))} = H \ket{\psi(\alpha(\tau))}$ to hold, we must have that the norm of the state $[\frac{d}{d\tau} + H] \ket{\psi(\alpha(\tau))}$ is vanishing, or equivalently that its projection onto the subspace containing $\frac{d}{d\tau} \ket{\psi(\alpha(\tau))}$ is vanishing, i.e. that there is no overlap between $[\frac{d}{d\tau} + H] \ket{\psi(\alpha(\tau))}$ and $\frac{d}{d\tau} \ket{\psi(\alpha(\tau))}$. The same argument holds for the state $[\Delta\frac{d}{d\tau} + \Delta H] \ket{\psi(\alpha(\tau))}$ formed by the deviation operators. From the overlap condition, we have explicitly
    $$0 = \sum_k \frac{d \alpha_k^\*}{d\tau}(\tau) \frac{\partial}{\partial \alpha_k} \bra{\psi(\alpha(\tau))} \bigg[ \sum_l \frac{d \alpha_l}{d\tau}(\tau) \frac{\partial}{\partial \alpha_l} \ket{\psi(\alpha(\tau))} - \sum_l \frac{d \alpha_l}{d\tau}(\tau) \langle \partial_l \rangle_{\psi(\alpha)} \ket{\psi(\alpha(\tau))} + H \ket{\psi(\alpha(\tau))} - \langle H \rangle_{\psi(\alpha)} \ket{\psi(\alpha(\tau))} \bigg] = \sum_k \frac{d \alpha_k^\*}{d\tau}(\tau) \bigg[ \sum_l \frac{d \alpha_l}{d\tau}(\tau) \langle \partial_k^\dagger \partial_l \rangle_{\psi(\alpha)} - \sum_l \frac{d \alpha_l}{d\tau}(\tau)  \langle \partial_k^\dagger \rangle_{\psi(\alpha)} \langle \partial_l \rangle_{\psi(\alpha)} + \langle \partial_k^\dagger H \rangle_{\psi(\alpha)} - \langle \partial_k^\dagger \rangle_{\psi(\alpha)} \langle H \rangle_{\psi(\alpha)} \bigg] = \sum_k \frac{d \alpha_k^\*}{d\tau}(\tau) \bigg[ \sum_l \frac{d \alpha_l}{d\tau}(\tau) S_{kl}(\alpha) + F_k(\alpha) \bigg]$$
which is true when each term is identically zero, i.e. when
    $$\sum_l \frac{d \alpha_l}{d\tau}(\tau) S_{kl}(\alpha) = - F_k(\alpha)$$
is true. This system of linear equations can be written in matrix form as
    $$S(\alpha) \frac{d \alpha}{d\tau}(\tau) = -F(\alpha)$$
whose formal solution is
    $$\frac{d \alpha}{d\tau}(\tau) = - S^{-1}(\alpha) F(\alpha)$$
such that
    $$\alpha(\tau + \delta \tau) \approx \alpha(\tau) + \delta\alpha(\tau) = \alpha(\tau) + \delta \tau \frac{d \alpha}{d\tau}(\tau) = \alpha(\tau) - \delta \tau S^{-1}(\alpha) F(\alpha)$$
is the infinitesimal change in the parameters $\alpha(\tau) \in \mathcal{M}$ due to the non-unitary, imaginary-time evolution of the state $\ket{\psi(\alpha(\tau))}$ over the interval $[\tau, \tau + \delta \tau]$.

It must be noted that the initialization of the parameters can have a dramatic effect on the performance of the algorithm. The initial state $\ket{\psi(\alpha(0))}$ must be chosen such that $\langle \psi_0, \psi(\alpha(0)) \rangle \neq 0$, or else learning is not possible. The more overlap there is with the ground state, the more efficient the algorithm will be. With at least some overlap, we will expect that $\ket{\psi(\alpha(\tau))} \to \ket{\psi_0}$ as $\tau \to \infty$ for a sufficiently small time step $\delta\tau$. This can be seen by noting the change in the energy functional over the interval $[\tau, \tau + \delta \tau]$, by taking the expectation of $H$ in the state $\ket{\psi(\alpha(\tau + \delta\tau))} \approx \ket{\psi(\alpha(\tau))} - \delta \tau \Delta H \ket{\psi(\alpha(\tau))} = \ket{\psi(\alpha(\tau))} + \delta \tau \Delta \frac{d}{d\tau} \ket{\psi(\alpha(\tau))}$, i.e.
    $$E[\psi(\alpha(\tau + \delta\tau))] = E[\psi(\alpha(\tau))] - 2\delta\tau F^\dagger(\alpha) S^{-1}(\alpha) F(\alpha) + \mathcal{O}(\delta\tau^2)$$
where $\mathcal{O}(\delta\tau^2)$ denotes the term involving $\delta\tau^2$. Since $\delta\tau > 0$ and $S(\alpha)$ is positive-definite, the second term will be strictly negative, such that the change in energy $E[\psi(\alpha(\tau + \delta\tau))] - E[\psi(\alpha(\tau))] < 0$ for a sufficiently small time step $\delta\tau$.

## Fortran Implementation

We implement the stochastic optimization algorithm as a type-bound procedure of a type `RestrictedBoltzmannMachine`:

```fortran
type RestrictedBoltzmannMachine
    private
    integer :: v_units = 0                                                !! Number of visible units
    integer :: h_units = 0                                                 !! Number of hidden units
    real(kind=rk),    allocatable, dimension(:)   :: a, p_a, r_a     !! Visible biases & ADAM arrays
    complex(kind=rk), allocatable, dimension(:)   :: b, p_b, r_b      !! Hidden biases & ADAM arrays
    complex(kind=rk), allocatable, dimension(:,:) :: w, p_w, r_w            !! Weights & ADAM arrays
    character(len=1) :: alignment = 'N'                               !! For tracking spin alignment
    logical          :: initialized = .false.                               !! Initialization status
    contains
        private
        procedure, pass(self), public :: stochastic_optimization          !! Public training routine
        procedure, pass(self)         :: init                              !! Initialization routine
        procedure, pass(self)         :: sample_distribution       !! MCMC routine for sampling p(s)
        procedure, pass(self)         :: prob_ratio               !! Probability ratio p(s_2)/p(s_1)
        procedure, pass(self)         :: ising_energy                          !! Ising local energy
        procedure, pass(self)         :: propagate        !! Routine for updating weights and biases
end type RestrictedBoltzmannMachine
```

In practice, we define the visible layer biases `a` as type `real` due to the fact that the logarithmic derivatives $O_{a_j}(s,a,b,w) = s_j$ are real for all $j \in [1,n]$ such that the imaginary component will remain zero over the course of learning. Additionally, we define complementary arrays for each `a`, `b`, and `w`, which we use to supplement the stochastic optimization algorithm with ADAM (Adaptive Moment Estimation) for the purpose of numerical stability and for smoothing the learning process for less well-behaved energy functionals. The following is a dependency tree for the type-bound procedures:

```text
RestrictedBoltzmannMachine
    |---stochastic_optimization
    |   |---init
    |   |---sample_distribution
    |   |   |---prob_ratio
    |   |   |---ising_energy
    |   |---propagate
```

The `stochastic_optimization` routine takes advantage of the coarray features of Fortran 2008 and, in particular, the collective subroutine extensions of Fortran 2018, allowing for many images of the program to run concurrently with collective communication. This allows us to average the weights across images in each epoch of learning, which dramatically improves stability and time to convergence in a stochastic framework.

From a main program, we simply need to initialize the random number generator, instantiate a `RestrictedBoltzmannMachine`, and call the `stochastic_optimization` routine with the desired Ising model parameters:

```fortran
call random_init(repeatable=.false., image_distinct=.true.)
psi = RestrictedBoltzmannMachine(v_units, h_units)
call psi%stochastic_optimization( ising_params=[J, B] )
```

The output data consists of energies and spin correlations, which will be written to separate `csv` files in the `/data` folder upon successful execution.

Note: with `init`, the biases are initialized to zero prior to training, and the weights have both real and imaginary parts initialized with samples from a standard Gaussian distribution using a routine adapted from [ROOT](https://root.cern.ch/doc/master/TRandom_8cxx_source.html#l00274).

## Building with fpm

The only dependency of this project is the Intel MKL distribution of LAPACK. With a system installation of [Intel oneAPI](https://www.intel.com/content/www/us/en/developer/tools/oneapi/toolkits.html) Base and HPC toolkits (including MKL), the project can be built and run on Windows 10/11 and Linux with [fpm](https://github.com/fortran-lang/fpm) from the project root using a single command, assuming the shell environment has sourced the oneAPI environment variables beforehand.

To target an $n$ core CPU with SIMD instructions, the project can be built and run on Windows 10/11 using the command

```powershell
fpm run --compiler ifort --flag "/Qcoarray /Qcoarray-num-images:n /Qopenmp /Qopenmp-simd" --link-flag "mkl_lapack95_lp64.lib mkl_intel_lp64.lib mkl_intel_thread.lib mkl_core.lib libiomp5md.lib"
```

and on Linux using the command

```bash
fpm run --compiler ifort --flag "-coarray -coarray-num-images=n -qopenmp -qopenmp-simd" --link-flag "-Wl,--start-group ${MKLROOT}/lib/intel64/libmkl_lapack95_lp64.a ${MKLROOT}/lib/intel64/libmkl_intel_lp64.a ${MKLROOT}/lib/intel64/libmkl_intel_thread.a ${MKLROOT}/lib/intel64/libmkl_core.a -liomp5 -lpthread -lm -ldl"
```

with equivalent features.

Here, `n` is the number of images to execute, which generally should equal the number of CPU cores available. We then enable the generation of multi-threaded code with OpenMP and SIMD compilation. Finally, the link flag specifies the MKL and OpenMP runtime libraries for static linking, provided by the [Intel Link Line Advisor](https://www.intel.com/content/www/us/en/developer/tools/oneapi/onemkl-link-line-advisor.html).

To target an $n$ core CPU and an Intel GPU for acceleration, the project can be built and run on Windows 10/11 using the command

```powershell
fpm run --compiler ifx --flag "/Qcoarray /Qcoarray-num-images:n /Qiopenmp /Qopenmp-targets:spir64 /Qopenmp-target-do-concurrent" --link-flag "mkl_lapack95_lp64.lib mkl_intel_lp64.lib mkl_intel_thread.lib mkl_core.lib libiomp5md.lib OpenCL.lib"
```

and on Linux using the command

```bash
fpm run --compiler ifx --flag "-coarray -coarray-num-images=n -fiopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent" --link-flag "-Wl,--start-group ${MKLROOT}/lib/intel64/libmkl_lapack95_lp64.a ${MKLROOT}/lib/intel64/libmkl_intel_lp64.a ${MKLROOT}/lib/intel64/libmkl_intel_thread.a ${MKLROOT}/lib/intel64/libmkl_core.a -liomp5 -lOpenCL -lpthread -lm -ldl"
```

with equivalent features.
