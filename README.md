# Learning Quantum States with Neural Networks

## Introduction

Quantum mechanics emerges from classical mechanics by the relaxation of the requirement of commutativity among the observables as assumed by classical probability theory. The most immediate and striking consequence of this relaxation is the insufficiency of real-valued probability distributions to encode the interference phenomena observed by experiment. In response, we generalize the notion of probability distributions from real-valued distributions over the set of possible outcomes which combine convexly, to complex-valued distributions over the set of possible outcomes which combine linearly. The complex-valued probabilities are able to encode the observed interference patterns in their relative phases. Such quantum probability distributions do not describe mutually exclusive outcomes in which only one outcome exists prior to measurement, but rather describes outcomes in which all possible outcomes simultaneously exist prior to measurement and which interfere in a wave-like manner.

The increase in predictive power offered by quantum mechanics came with the price of computational difficulties. Unlike the classical world, whose dimensionality scales additively with the number of subsystems, the dimensionality scaling of quantum systems is multiplicative. Thus, even small systems quickly become intractable without approximation techniques. Luckily, it is rarely the case that knowledge of the full state space is required to accurately model a given system, as most information may be contained in a relatively small subspace. Many of the most successful approximation techniques of the last century, such as Born–Oppenheimer and variational techniques like Density Functional Theory, rely on this convenient notion for their success. With the rapid development of machine learning, a field which specializes in dimensionality reduction and feature extraction of very large datasets, it is natural to apply these novel techniques for dealing with the canonical large data problem of the physical sciences.

## Restricted Boltzmann Machines

The Universal Approximation Theorems are a collection of results concerning the ability of artificial neural networks to arbitrarily approximate different classes of functions. In particular, the Restricted Boltzmann Machine (RBM) is a shallow two-layer network consisting of $n$ input nodes or *visible units*, and $m$ output nodes or *hidden units* such that each input $v \in \{0,1\}^n$ and output $h \in \{0,1\}^m$ are Boolean vectors of respective length. The standard RBM is characterized by parameters $\{a,b,w\}$ where $a \in \mathbb{R}^n$ are the visible layer biases, $b \in \mathbb{R}^m$ are the hidden layer biases, and $w \in \mathbb{R}^{m \times n}$ are the weights which fully connect the layers. The network is "restricted" in the sense that there are no intra-layers connections.

Let $V = \{0,1\}^n$ be the set of inputs, let $H = \{0,1\}^m$ be the set of outputs, and let $X = V \times H$ be the set of pairs. Then the RBM is a universal approximator of Boltzmann probability distributions $p:X \to [0,1]$ defined by
    $$X \ni (v,h) \mapsto p(v,h) = \frac{\exp[-E(v,h)]}{Z} = \frac{\exp(a^\perp v + b^\perp h + h^\perp wv)}{\sum_{(v',h') \in X} \exp(a^\perp v' + b^\perp h' + {h'}^\perp wv')} \in [0,1]$$
where $E(v,h) = -a^\perp v - b^\perp h - h^\perp wv$ is the dimensionless energy and $Z = \sum_{(v',h') \in X} \exp(a^\perp v' + b^\perp h' + {h'}^\perp wv')$ is the partition function which normalizes the probabilities, with $\perp$ denoting the matrix transpose. From the joint probability distribution $p$, we may construct the marginal distributions $p_V = p|V:V \to [0,1]$ and $p_H = p|H: H \to [0,1]$ as the partial sums
    $$p_V(v) = \sum_{h \in H} p(v,h)~~,~~p_H(h) = \sum_{v \in V} p(v,h)$$
over $H$ and $V$ respectively. Due to the restricted nature of the RBM, the activation probabilities $p(h_i=1|v)$ and $p(v_j=1|h)$ of each layer are mutually exclusive for all $i \in [1,m]$ and $j \in [1,n]$ such that the conditional probabilities are the products
    $$p(h|v) = \prod_{i=1}^m p(h_i=1|v)~~,~~p(v|h) = \prod_{j=1}^n p(v_j=1|h)$$
of activation probabilities. The traditional method for training an RBM involves [Hinton](https://en.wikipedia.org/wiki/Geoffrey_Hinton)'s Contrastive Divergence technique, which will not be covered here.

## Neural Network Quantum States

A variational approach to solving the Schrödinger equation involves proposing a parametrized trial wave-function and minimizing an associated energy functional by varying the internal parameters until a global minimum is found. Recasting this problem in the language of neural networks, we may introduce a trial wave-function $\psi$ as the marginal of the inputs of a Restricted Boltzmann Machine with complex parameters $\{a,b,w\}$ where $a \in \mathbb{C}^n$ are the visible layer biases, $b \in \mathbb{C}^m$ are the hidden layer biases, and $w \in \mathbb{C}^{m \times n}$ are the weights which fully connect the layers.

Since the RBM works with Boolean vectors, the RBM is a natural choice for representing wave-functions of systems of spin-$\tfrac{1}{2}$ particles where each input $s \in \{0,1\}^n$ represents a configuration of $n$ spins. Letting $S = \{0,1\}^n$ be the set of inputs and $H = \{0,1\}^m$ be the set of outputs, the RBM with complex parameters is a universal approximator of complex probability distributions $\Psi:S \times H \to \mathbb{C}$ such that the trial wave-function $\psi = \Psi|S:S \to \mathbb{C}$ is the marginal distribution defined by
    $$\begin{align*}
    S \ni s \mapsto \psi(s) = \sum_{h \in H} \Psi(s,h) = \sum_{h \in H} \exp[-E(s,h)] &= \sum_{h \in H} \exp(a^\dagger s + b^\dagger h + h^\dagger ws) \\
    &= \exp(a^\dagger s) \sum_{h \in H} \exp(b^\dagger h + h^\dagger ws) \\
    &= \exp\bigg(\sum_{j=1}^n a_j^* s_j\bigg) \sum_{h \in H} \exp\bigg(\sum_{i=1}^m b_i^*h_i + \sum_{i=1}^m h_i \sum_{j=1}^n w_{ij} s_j\bigg) \\
    &= \exp\bigg(\sum_{j=1}^n a_j^* s_j\bigg) \sum_{h \in H} \prod_{i=1}^m \exp\bigg(b_i^*h_i + h_i \sum_{j=1}^n w_{ij} s_j\bigg) \\
    &= \exp\bigg(\sum_{j=1}^n a_j^* s_j\bigg) \prod_{i=1}^m \sum_{h_i=0}^1 \exp\bigg(b_i^*h_i + h_i \sum_{j=1}^n w_{ij} s_j\bigg) \\
    &= \exp\bigg(\sum_{j=1}^n a_j^* s_j\bigg) \prod_{i=1}^m \bigg[ 1 + \exp\bigg(b_i^* + \sum_{j=1}^n w_{ij} s_j\bigg)\bigg] \in \mathbb{C} \\
    \end{align*}$$
where we ignore the normalization factor $Z$ of the wave-function, and where $\dagger$ represents the matrix conjugate transpose. By the Born rule, the real, normalized probability distribution $p:S \to [0,1]$ associated to our wave-function $\psi$ is defined by $S \ni s \mapsto p(s) = |\psi(s)|^2/\sum_{s' \in S} |\psi(s')|^2 \in [0,1]$.

The state space $\mathbb{C}^{2^n}$ of the $n$-particle system has dimension $2^n$, and we may choose an orthonormal basis $\{\ket{s}\} \subset \mathbb{C}^{2^n}$ labeled by the configurations $s \in S$ such that the most general state is a linear combination $\ket{\psi} = \sum_{s \in S} \psi(s) \ket{s} \in \mathbb{C}^{2^n}$. For the RBM's cost function, we take the statistical expectation $\langle H \rangle_\psi$ of the Hamiltonian $H$ in the state $\ket{\psi}$ and attempt to minimize this cost function through the process of training the RBM. We have
    $$\langle H \rangle_\psi = \frac{\langle \psi, H\psi \rangle}{\langle \psi, \psi \rangle} =
    \frac{\sum_{s,s' \in S} \psi^*(s) H_{ss'} \psi(s')}{\sum_{s' \in S} |\psi(s')|^2} =
    \frac{\sum_{s \in S} |\psi(s)|^2 \left(\sum_{s' \in S} H_{ss'} \frac{\psi(s')}{\psi(s)}\right)}{\sum_{s' \in S} |\psi(s')|^2} =
    \sum_{s \in S} p(s) E_{\text{loc}}(s)$$
where we define the local energies $E_{\text{loc}}(s) = \sum_{s' \in S} H_{ss'} \frac{\psi(s')}{\psi(s)}$, with $H_{ss'}$ being the matrix element of $H$ in between the states $\ket{s}$ and $\ket{s'}$. Thus $\langle H \rangle_\psi = \sum_{s \in S} p(s) E_{\text{loc}}(s)$ is the statistical expectation of the local energy described by the probability distribution $p:S \to [0,1]$.

## Transverse Field Ising Model

In this demonstration, we assume the prototypical Ising spin model for a one-dimensional lattice of spin-$\tfrac{1}{2}$ particles, whose Hamiltonian is given by
    $$H = -J \sum_{j=1}^{n-1} \sigma_j^z \sigma_{j+1}^z - B \sum_{j=1}^n \sigma_x$$
where we use the shorthand notation $\sigma_j^z \sigma_{j+1}^z = I^{(1)} \otimes \cdots \otimes \sigma_z^{(j)} \otimes \sigma_z^{(j+1)} \otimes \cdots \otimes I^{(n)}$ to denote the tensor product of the $2 \times 2$ identity matrix with the Pauli matrix $\sigma_z$ located at positions $j$ and $j+1$, and where $\sigma_x = I^{(1)} \otimes \cdots \otimes \sigma_x^{(j)} \otimes \cdots \otimes I^{(n)}$ denotes $\sigma_x$ at position $j$. The size of $H$ is $2^n \times 2^n$, and so it is impossible to directly diagonalize even for relatively few particles. The constant $J$ represents the nearest neighbor coupling strength, and $B$ represents the strength of the transverse field. When $J>0$, nearest neighbors tend to align parallel (ferromagnetic), and tend to align anti-parallel when $J<0$ (anti-ferromagnetic). The local energy of a configuration $s \in S$ in the Ising model can easily be seen to be
    $$E_{\text{loc}}(s) =-J \sum_{j=1}^{n-1} \sigma_j \sigma_{j+1} - B \sum_{s' \in F_s} \frac{\psi(s')}{\psi(s)}$$
where $\sigma_j = -2s_j + 1 \in \{1,-1\}$ and $F_s$ consists of $n$ configurations in which a single spin of $s$ has been inverted.

## Training
