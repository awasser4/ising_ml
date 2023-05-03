module nnqs
    !-------------------------------------------------------------------------------------------------------------------
    !! This module contains an implementation of the stochastic optimization algorithm for learning the ground state
    !! of the Ising spin model by representing the wave-functions ψ(s,α) as a type RestrictedBoltzmannMachine.
    !-------------------------------------------------------------------------------------------------------------------
    use, intrinsic :: iso_fortran_env, only: rk=>real64, ik=>int8, int64, compiler_version, compiler_options
    use, intrinsic :: ieee_arithmetic, only: ieee_is_nan
    use, intrinsic :: ieee_exceptions, only: ieee_set_halting_mode, ieee_invalid, ieee_divide_by_zero
    use io_fortran_lib, only: echo, LF, str, to_file                                     !! I/O procedures and constants
    use lapack95, only: ppsvx                                  !! Routine for solving linear systems with packed storage
    implicit none (type,external)                                                     !! No implicit types or interfaces
    private                             !! All objects in scope are inaccessible outside of scope unless declared public

    !! Public API list ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    public :: RestrictedBoltzmannMachine

    !! Definitions and Interfaces ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    type RestrictedBoltzmannMachine
        private
        integer :: v_units = 0                                                                !! Number of visible units
        integer :: h_units = 0                                                                 !! Number of hidden units
        real(rk),    allocatable, dimension(:)   :: a, p_a, r_a                    !! Visible layer biases & ADAM arrays
        complex(rk), allocatable, dimension(:)   :: b, p_b, r_b                     !! Hidden layer biases & ADAM arrays
        complex(rk), allocatable, dimension(:,:) :: w, p_w, r_w                                 !! Weights & ADAM arrays
        character(len=1) :: alignment = 'N'                                               !! For tracking spin alignment
        contains
            private
            procedure, pass(self), public :: stochastic_optimization                          !! Public training routine
            procedure, pass(self)         :: init                                              !! Initialization routine
            procedure, pass(self)         :: sample_distribution                      !! MCMC routine for sampling |ψ|^2
            procedure, pass(self)         :: prob_ratio                           !! Probability ratio |ψ(s_2)/ψ(s_1)|^2
            procedure, pass(self)         :: ising_energy                                          !! Ising local energy
            procedure, pass(self)         :: propagate                        !! Routine for updating weights and biases
    end type RestrictedBoltzmannMachine

    interface RestrictedBoltzmannMachine
        procedure :: new_rbm                                              !! Constructor function with same name as type
    end interface

    contains !!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    pure recursive type(RestrictedBoltzmannMachine) function new_rbm(v_units, h_units) result(new)
        !---------------------------------------------------------------------------------------------------------------
        !! Function for constructing a RestrictedBoltzmannMachine
        !---------------------------------------------------------------------------------------------------------------
        integer, intent(in) :: v_units, h_units                       ! Number of visible and hidden units to initialize
        new%v_units = v_units                       !! Set number of visible units (always equal to the number of spins)
        new%h_units = h_units                    !! Set number of hidden units (chosen arbitrarily to optimize learning)
    end function new_rbm

    impure recursive subroutine stochastic_optimization(self, ising_strengths)
        !---------------------------------------------------------------------------------------------------------------
        !! Public routine for training RBM
        !---------------------------------------------------------------------------------------------------------------
        class(RestrictedBoltzmannMachine), intent(inout) :: self                                    !! Boltzmann machine
        real(rk), contiguous, dimension(:), intent(in)   :: ising_strengths                          !! Ising parameters

        integer(ik), allocatable, dimension(:)   :: start_sample                         !! Start sample for Monte Carlo
        integer(ik), allocatable, dimension(:,:) :: samples                                      !! Sample storage array
        integer :: epoch, max_epochs, num_samples, n, m           !! Loop variable, max epochs, number of samples, spins

        real(rk),    allocatable, dimension(:)   :: e_loc, corrs                  !! Local energies, sample correlations
        real(rk),    allocatable, dimension(:,:) :: energies, correlations                  !! Energies and correlations
        complex(rk), allocatable, dimension(:)   :: theta                                 !! θ = b + ws for start sample
        real(rk) :: energy, sqerr, stderr, tau, acc                                               !! Recording variables

        character(len=:), allocatable :: logfile, logmsg                                          !! Recording variables
        character(len=10)             :: date, time                                                     !! Date and time

        integer(int64) :: t1, t2                                                                      !! Clock variables
        real(rk)       :: rate, wall_time                                                             !! Clock variables

        if ( this_image() == 1 ) then                                     !! Check validity of Ising strength parameters
            if ( size(ising_strengths) /= 2 ) then
                error stop  LF//'FATAL: Invalid size for ising_strengths... size must be (2).'// &
                            LF//'USAGE: ising_strengths = [J,B] where J is the neighbor coupling strength and B '// &
                                'is the transverse field strength.'//LF
            end if
            if ( abs(ising_strengths(2)) >= 1.0_rk ) then
                error stop LF//'FATAL: Invalid field strength parameter... try again with |B| < 1.'//LF
            end if
            sync images (*)                                                                   !! Respond to other images
        else
            sync images (1)                                                            !! Wait for response from image 1
        end if

        ! call ieee_set_halting_mode([ieee_divide_by_zero, ieee_invalid], halting=.true.)                         !! Debug

        call self%init()                                                                 !! Initialize Boltzmann machine

        if ( ising_strengths(1) < 0.0_rk ) then                                       !! Check sign of coupling strength
            self%alignment = 'A'                                                          !! Anti-ferromagnetic if J < 0
        else
            self%alignment = 'F'                                                               !! Ferromagnetic if J > 0
        end if

        n = self%v_units                                                                          !! Get number of spins
        m = self%h_units                                                                   !! Get number of hidden units
        max_epochs = 1000                                                                          !! Set maximum epochs
        num_samples = 15                                                             !! Set number of samples to produce

        allocate( start_sample(n), samples(num_samples, n), source=0_ik )                      !! Initialize work arrays
        allocate( e_loc(num_samples), corrs(n), source=0.0_rk )                                !! Initialize work arrays

        call random_sample(start_sample)                                                !! Randomize the starting sample
        theta = conjg(self%b) + matmul(self%w, start_sample)                                            !! Get initial θ

        if ( this_image() == 1 ) then                                                       !! Do preparation on image 1
            allocate( energies(max_epochs, 2), correlations(n, max_epochs), source=0.0_rk ) !! Initialize storage arrays

            logfile = 'optimization_results.log'                                                         !! Set log file
            call date_and_time(date=date, time=time)                                                !! Get date and time

            logmsg = 'Stochastic Optimization - date: '//trim(adjustl(date))//' | time: '//time    !! Training log title
            call echo(logmsg//LF//repeat('-', ncopies=len(logmsg))//LF, file_name=logfile)               !! Echo to file

            call system_clock(t1)                                                                         !! Start timer
        end if

        learning: do epoch = 1, max_epochs                                                             !! Begin learning
            call co_sum(self%w); self%w = self%w/num_images()                           !! Average weights across images

            call self%sample_distribution(epoch=epoch, ising_strengths=ising_strengths, &                      !! Inputs
                                          start_sample=start_sample, theta=theta, &                     !! Input/outputs
                                          samples=samples, e_loc=e_loc, corrs=corrs, &                  !! Array outputs
                                          energy=energy, sqerr=sqerr)                                  !! Scalar outputs

            call co_sum(energy); energy = energy/num_images()                            !! Average energy across images
            call co_sum(sqerr);  stderr = sqrt(sqerr)/num_images()                        !! Average error across images
            call co_sum(corrs);  corrs = corrs/num_images()                        !! Average correlations across images

            if ( this_image() == 1 ) then                                                !! Do data recording on image 1
                energies(epoch,:) = [energy, stderr]                               !! Record energy and error to storage
                correlations(:,epoch) = corrs                                          !! Record correlations to storage

                !! Write progress report ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
                if ( n < 100 ) then                                                                !! Set imaginary time
                    tau = (epoch-1)*1.0_rk/n
                else
                    tau = (epoch-1)*10.0_rk/n
                end if

                logmsg = '    Epoch '//str(epoch)//': E[ψ(α(τ='//str(tau, fmt='f', decimals=3)//'))] = '// &
                         str(energy, fmt='f', decimals=3)//' ± '//str(stderr, fmt='f', decimals=3)

                call echo(logmsg, logfile)                                                         !! Record log message
                write(unit=*, fmt='(a)') logmsg                                                     !! Print log message

                if ( ieee_is_nan(energy) ) error stop LF//'FATAL: Numerical instability.'           !! Error termination
                sync images (*)                                                               !! Respond to other images
            else
                sync images (1)                                                        !! Wait for response from image 1
            end if

            acc = 1.0_rk - real(count(samples == 0_ik), kind=rk)/size(samples)              !! Get ground state accuracy
            call co_sum(acc); acc = acc/num_images()                                   !! Average accuracy across images
            if ( (acc > 0.9999_rk) .or. (epoch == max_epochs) ) exit learning                         !! Exit conditions

            e_loc = e_loc - sum(e_loc)/num_samples                                          !! Center the local energies
            call self%propagate(epoch=epoch, e_loc=e_loc, samples=samples)                          !! Update parameters
        end do learning

        if ( this_image() == 1 ) then                                              !! Do finalization and I/O on image 1
            call system_clock(t2, count_rate=rate); wall_time = real(t2-t1, kind=rk)/rate               !! Get time in s

            logmsg = LF//'    Optimization time: '//str(wall_time, fmt='f', decimals=3)//' seconds for n = '// &
                         str(n)//' spins.'// &
                     LF//'    Ground state energy: E[ψ(α(τ → ∞))] = '//str(energy, fmt='f', decimals=3)// &
                         ' ± '//str(stderr, fmt='f', decimals=3)//' for J = '// &
                         str(ising_strengths(1), fmt='f', decimals=1)//' and B = '// &
                         str(ising_strengths(2), fmt='f', decimals=1)// &
                     LF//'    Ground state accuracy: '//str(acc, fmt='f', decimals=6)//LF// &
                     LF//'    This program was built and run with compiler "'//compiler_version()//'" '// &
                         'using compiler options "'//compiler_options()//'".'//LF

            call echo(logmsg, logfile)
            call to_file(energies(:epoch,:), './data/energies_'//self%alignment//'.csv', header=['Energy', 'Error'] )
            call to_file(correlations(:,:epoch), './data/correlations_'//self%alignment//'.csv', header=['Epoch'] )
        end if
    end subroutine stochastic_optimization

    impure recursive subroutine init(self)
        !---------------------------------------------------------------------------------------------------------------
        !! Procedure for initialization
        !---------------------------------------------------------------------------------------------------------------
        class(RestrictedBoltzmannMachine), intent(inout) :: self                                    !! Boltzmann machine
        integer :: n, m, i, j                                                                !! Sizes and loop variables

        n = self%v_units                                                                          !! Get number of spins
        m = self%h_units                                                                   !! Get number of hidden units

        if ( this_image() == 1 ) then
            if ( (n < 1) .or. (m < 1) ) then
                error stop LF//'FATAL: Structure has not been declared or has invalid number of units.'
            end if
            sync images (*)                                                                   !! Respond to other images
        else
            sync images (1)                                                            !! Wait for response from image 1
        end if

        if ( allocated(self%a) ) deallocate(self%a, self%p_a, self%r_a, &
                                            self%b, self%p_b, self%r_b, &
                                            self%w, self%p_w, self%r_w)                    !! Reset components if needed

        allocate( self%a(n), self%p_a(n), self%r_a(n), source=0.0_rk )             !! Allocate visible layer bias arrays
        allocate( self%b(m), self%p_b(m), self%r_b(m), source=(0.0_rk,0.0_rk) )     !! Allocate hidden layer bias arrays
        allocate( self%w(m,n), self%p_w(m,n), self%r_w(m,n), source=(0.0_rk,0.0_rk) )          !! Allocate weight arrays

        do j = 1, n
            do i = 1, m
                self%w(i,j) = cmplx( gauss(mu=0.01_rk, sig=1e-4_rk), gauss(mu=-0.005_rk, sig=1e-5_rk), kind=rk )
            end do
        end do
    end subroutine init

    impure recursive subroutine sample_distribution(self, epoch, ising_strengths, start_sample, theta, samples, &
                                                    e_loc, corrs, energy, sqerr)
        !---------------------------------------------------------------------------------------------------------------
        !! Markov Chain Monte Carlo procedure for sampling |ψ|^2 with Metropolis-Hastings algorithm
        !---------------------------------------------------------------------------------------------------------------
        class(RestrictedBoltzmannMachine), intent(in) :: self                              !! Distribution to be sampled
        integer, intent(in) :: epoch                                                                    !! Current epoch
        real(rk),    contiguous, dimension(:),   intent(in)    :: ising_strengths                    !! Ising parameters
        integer(ik), contiguous, dimension(:),   intent(inout) :: start_sample         !! Sample to begin thermalization
        complex(rk), contiguous, dimension(:),   intent(inout) :: theta                   !! θ = b + ws for start sample
        integer(ik), contiguous, dimension(:,:), intent(out)   :: samples                              !! Output samples
        real(rk),    contiguous, dimension(:),   intent(out)   :: e_loc, corrs    !! Local energies, sample correlations
        real(rk), intent(out) :: energy, sqerr                                           !! Energy average, square error

        real(rk) :: acc_prob                                                               !! M-H acceptance probability
        integer  :: n, m, passes, num_samples                          !! Number of spins, hidden units, passes, samples

        n = self%v_units                                                                          !! Get number of spins
        m = self%h_units                                                                   !! Get number of hidden units
        num_samples = size(samples, dim=1)                                               !! Number of samples to produce

        thermalization: block
            integer(ik), dimension(n) :: s_prop                                                       !! Proposal sample
            integer  :: k, max_thermal_time, rind                                        !! Loop variables, random index
            real(rk) :: r                                                                               !! Random number

            max_thermal_time = 2001 - 2*epoch                                       !! Set time limit for thermalization
            s_prop = start_sample                                                                   !! Copy start sample

            thermalize: do k = 1, max_thermal_time
                call random_number(r); rind = floor(n*r) + 1                                    !! Generate random index
                s_prop(rind) = 1_ik - s_prop(rind)                                          !! Flip spin at random index
                acc_prob = self%prob_ratio(s1=start_sample, s2=s_prop, theta1=theta)           !! Acceptance probability

                call random_number(r)                                       !! Sample from uniform distribution on [0,1)
                if ( r < acc_prob ) then                                                     !! M-H acceptance criterion
                    theta = theta + self%w(:,rind)*(s_prop(rind) - start_sample(rind))                       !! Update θ
                    start_sample(rind) = s_prop(rind)                                                   !! Update sample
                else
                    s_prop(rind) = 1_ik - s_prop(rind)                                                   !! Reverse flip
                end if
            end do thermalize
        end block thermalization

        passes = 2*n - min(2*epoch, 2*n-1)                               !! Number of passes to make on the start sample

        stationary_sampling: block
            complex(rk), dimension(m)                   :: theta_loc                                          !! Local θ
            real(rk),    dimension(passes, num_samples) :: r                                           !! Random numbers
            integer(ik), dimension(n)                   :: s, s_prop                            !! Sample storage arrays
            integer,     dimension(passes, num_samples) :: rind                                        !! Random indices
            integer :: k, pass                                                                         !! Loop variables

            call random_number(r); rind = floor(n*r) + 1                             !! Generate random indices in [1,n]
            call random_number(r)                                                                  !! Repopulate randoms

            do concurrent (k = 1:num_samples) default(none) shared(start_sample, theta, passes, rind, self, r, &
                                              samples, e_loc, ising_strengths, num_samples) &
                                              local(s, theta_loc, s_prop, pass, acc_prob)
                s = start_sample                                                            !! Copy start sample to temp
                theta_loc = theta                                                                  !! Copy theta to temp
                s_prop = s                                                                           !! Copy temp sample

                metropolis_hastings: do pass = 1, passes
                    s_prop(rind(pass, k)) = 1_ik - s_prop(rind(pass, k))                    !! Flip spin at random index
                    acc_prob = self%prob_ratio(s1=s, s2=s_prop, theta1=theta_loc)              !! Acceptance probability

                    if ( r(pass, k) < acc_prob ) then                                        !! M-H acceptance criterion
                        theta_loc = theta_loc + self%w(:,rind(pass,k))*(s_prop(rind(pass, k)) - s(rind(pass,k)))!! New θ
                        s(rind(pass, k)) = s_prop(rind(pass, k))                                        !! Update sample
                    else
                        s_prop(rind(pass, k)) = 1_ik - s_prop(rind(pass, k))                             !! Reverse flip
                    end if
                end do metropolis_hastings

                samples(k,:) = s                                                            !! Transfer sample to output
                e_loc(k) = self%ising_energy(s=s, theta=theta_loc, ising_strengths=ising_strengths) !! Local energy of s

                if ( k == num_samples ) then
                    theta = theta_loc                                        !! Record θ to begin next round of sampling
                    start_sample = s                         !! Record stationary sample to begin next round of sampling
                end if
            end do
        end block stationary_sampling

        call get_correlations(samples, corrs=corrs, alignment=self%alignment)        !! Get spin correlations of samples
        energy = sum(e_loc)/num_samples                                                           !! Average of energies
        sqerr = var(e_loc)/num_samples                                                       !! Square error of energies
    end subroutine sample_distribution

    pure recursive real(rk) function prob_ratio(self, s1, s2, theta1) result(p)
        !---------------------------------------------------------------------------------------------------------------
        !! Function for computing the ratio of probabilities |ψ(s_2)/ψ(s_1)|^2 for two given configurations
        !---------------------------------------------------------------------------------------------------------------
        class(RestrictedBoltzmannMachine), intent(in) :: self                                       !! Boltzmann machine
        integer(ik), contiguous, dimension(:), intent(in) :: s1, s2                                    !! Configurations
        complex(rk), contiguous, dimension(:), intent(in) :: theta1                          !! Cached value of b + ws_1

        complex(rk), dimension(self%h_units) :: theta2                                                       !! b + ws_2
        complex(rk) :: prob_amplitude_ratio                                                             !! ψ(s_2)/ψ(s_1)
        real(rk)    :: s                                                                                           !! ±1
        integer     :: i                                                                                !! Loop variable

        i = 1; do
            if ( (s2(i) - s1(i)) /= 0_ik ) exit
            i = i + 1; cycle
        end do

        s = real(s2(i) - s1(i), kind=rk)
        theta2 = theta1 + self%w(:,i)*s                                                                  !! Get b + ws_2
        prob_amplitude_ratio = exp(self%a(i)*s + sum(log(1.0_rk+exp(theta2)) - log(1.0_rk+exp(theta1)))) !!ψ(s_2)/ψ(s_1)
        p = real(conjg(prob_amplitude_ratio)*prob_amplitude_ratio, kind=rk)                         !! |ψ(s_2)/ψ(s_1)|^2
    end function prob_ratio

    pure recursive real(rk) function ising_energy(self, s, theta, ising_strengths) result(energy)
        !---------------------------------------------------------------------------------------------------------------
        !! Function for calculating local energy of configuration s in Ising model
        !---------------------------------------------------------------------------------------------------------------
        class(RestrictedBoltzmannMachine), intent(in) :: self                                       !! Boltzmann machine
        integer(ik), contiguous, dimension(:), intent(in) :: s                                    !! Configuration input
        complex(rk), contiguous, dimension(:), intent(in) :: theta                             !! Cached value of b + ws
        real(rk),    contiguous, dimension(:), intent(in) :: ising_strengths                         !! Ising parameters

        real(rk) :: J_str, B_str, e_coupling, e_transverse       !! Ising parameters, coupling energy, transverse energy
        integer  :: j, n, m                                              !! Loop variable, number of spins, hidden units

        n = self%v_units                                                                          !! Get number of spins
        m = self%h_units                                                                   !! Get number of hidden units
        J_str = abs(ising_strengths(1)); B_str = abs(ising_strengths(2))     !! Set coupling strength and field strength
        e_coupling = 0.0_rk; e_transverse = 0.0_rk                                                         !! Initialize

        interaction: block
            real(rk),    dimension(n) :: s_map, field_couplings                                            !! 1 + exp(θ)
            complex(rk), dimension(m) :: arg_theta                                                            !! s -> ±1

            s_map = -2.0_rk*s + 1.0_rk                                                          !! Map {0,1} -> {1.,-1.}
            arg_theta = 1.0_rk + exp(theta)                                                    !! 1 + exp(θ) for input s

            do j = 1, n
            ! do concurrent (j = 1:n) default(none) shared(field_couplings, self, s_map, theta, arg_theta)
                field_couplings(j) = exp( self%a(j)*s_map(j) + &                                !! ψ(s')/ψ(s) for all s'
                sum(log(1.0_rk + exp(theta + self%w(:,j)*s_map(j))) - log(arg_theta)) )         !! Forget imaginary part
            end do

            e_coupling = -J_str*sum(s_map(1:n-1)*s_map(2:n))                !! Local energy due to neighbor interactions
            e_transverse = -B_str*sum(field_couplings)                           !! Local energy due to transverse field
            energy = e_coupling + e_transverse          !! Local energy is sum of coupling and transverse field energies
        end block interaction
    end function ising_energy

    pure recursive subroutine propagate(self, epoch, e_loc, samples)
        !---------------------------------------------------------------------------------------------------------------
        !! Procedure for updating parameters according to stochastic optimization update rule
        !---------------------------------------------------------------------------------------------------------------
        class(RestrictedBoltzmannMachine), intent(inout) :: self                                    !! Boltzmann machine
        integer, intent(in) :: epoch                                                                    !! Current epoch
        real(rk),    contiguous, dimension(:),   intent(in) :: e_loc                                   !! Local energies
        integer(ik), contiguous, dimension(:,:), intent(in) :: samples                                 !! Network inputs

        real(rk) :: covar_norm, delta, beta_1, beta_2, epsilon, dtau         !! Normalization, regularization, ADAM vars
        integer  :: n, m, num_samples, i, ii, j, jj, k, ind                                   !! Size and loop variables

        n = self%v_units                                                                          !! Get number of spins
        m = self%h_units                                                                   !! Get number of hidden units
        num_samples = size(samples, dim=1)                                                      !! Get number of samples
        covar_norm = 1.0_rk/(num_samples - 1)                                     !! Set sample covariance normalization
        delta = 1e-5_rk                                                                  !! Set regularization parameter
        beta_1 = 0.99_rk                                                                  !! Decay rate for first moment
        beta_2 = 0.999_rk                                                                !! Decay rate for second moment
        epsilon = 1e-8_rk                                                       !! Parameter to prevent division by zero

        if ( n < 100 ) then                                                                            !! Set time step
            dtau = 1.0_rk/n
        else
            dtau = 10.0_rk/n
        end if

        propagation: block
            real(rk),    dimension(num_samples, n)    :: O_a                        !! Log derivatives with respect to a
            complex(rk), dimension(num_samples, m)    :: O_b                        !! Log derivatives with respect to b
            complex(rk), dimension(num_samples, m, n) :: O_w                        !! Log derivatives with respect to w

            real(rk), dimension(n)           :: F_a, x_a                              !! Forces and solution array for a
            real(rk), dimension((n*(n+1))/2) :: S_a                                                   !! SR matrix for a

            complex(rk), dimension(m)           :: F_b, x_b                           !! Forces and solution array for b
            complex(rk), dimension((m*(m+1))/2) :: S_b                                                !! SR matrix for b

            complex(rk), dimension(m, n)           :: F_w, x_w                        !! Forces and solution array for w
            complex(rk), dimension((m*(m+1))/2, n) :: S_w                                             !! SR matrix for w

            O_a = 0.0_rk; F_a = 0.0_rk; x_a = 0.0_rk; S_a = 0.0_rk                                         !! Initialize
            O_b = (0.0_rk, 0.0_rk); F_b = (0.0_rk, 0.0_rk); x_b = (0.0_rk, 0.0_rk); S_b = (0.0_rk, 0.0_rk) !! Initialize
            O_w = (0.0_rk, 0.0_rk); F_w = (0.0_rk, 0.0_rk); x_w = (0.0_rk, 0.0_rk); S_w = (0.0_rk, 0.0_rk) !! Initialize

            !! Logarithmic Derivatives ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            O_a = real(samples, kind=rk)                                          !! O_a(k,j) = 𝜕/𝜕a_j ln ψ(s^k) = s_j^k

            O_b = matmul(samples, transpose(self%w))                                           !! ws^k for all samples k
            do concurrent (i = 1:m) default(none) shared(self, O_b)
                O_b(:,i) = exp(conjg(self%b(i)) + O_b(:,i))  !! exp(θ_i^k) = exp(b_i + Σ_j w_ij*s_j^k) for all samples k
                O_b(:,i) = O_b(:,i)/(1.0_rk + O_b(:,i))     !! O_b(k,i) = 𝜕/𝜕b_i ln ψ(s^k) = exp(θ_i^k)/(1 + exp(θ_i^k))
            end do

            do concurrent (j = 1:n, i = 1:m) default(none) shared(O_a, O_b, O_w)
                O_w(:,i,j) = O_a(:,j)*O_b(:,i)     !! O_w(k,i,j) = 𝜕/𝜕w_ij ln ψ(s^k) = s_j^k exp(θ_i^k)/(1 + exp(θ_i^k))
            end do
            !! End Logarithmic Derivatives ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            !! Propagate a ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            do concurrent (j = 1:n) default(none) shared(O_a, F_a, e_loc, num_samples, covar_norm)
                O_a(:,j) = O_a(:,j) - sum(O_a(:,j))/num_samples                     !! Center each column about its mean
                F_a(j) = sum(O_a(:,j)*e_loc)*covar_norm                                        !! F(j) = ⟨Δ∂_{a_j}^† ΔH⟩
            end do

            do concurrent (jj = 1:n, j = 1:n, j >= jj) default(none) shared(S_a, O_a, covar_norm, delta, n) local(ind)
                ind = n*(jj-1) - ((jj-2)*(jj-1))/2 + (j-jj) + 1                                  !! Packed index mapping
                S_a(ind) = sum(O_a(:,j)*O_a(:,jj))*covar_norm                                              !! Covariance
                if (j == jj) S_a(ind) = S_a(ind) + delta                              !! Add regularization to diagonals
            end do

            call ppsvx(AP=S_a, b=F_a, x=x_a, uplo='L', fact='E')               !! Stochastic reconfiguration x = S^{-1}F

            self%p_a = beta_1*self%p_a + (1.0_rk - beta_1)*x_a                           !! Biased first moment estimate
            self%r_a = beta_2*self%r_a + (1.0_rk - beta_2)*(x_a**2)                 !! Biased second raw moment estimate
            x_a = ( self%p_a/(1.0_rk - beta_1**epoch) )/sqrt( (self%r_a/(1.0_rk - beta_2**epoch)) + epsilon )    !! ADAM
            self%a = self%a - dtau*x_a                                                          !! Update visible biases
            !! End Propagate a ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            !! Propagate b ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            do concurrent (i = 1:m) default(none) shared(O_b, F_b, e_loc, num_samples, covar_norm)
                O_b(:,i) = O_b(:,i) - sum(O_b(:,i))/num_samples                     !! Center each column about its mean
                F_b(i) = sum(conjg(O_b(:,i))*e_loc)*covar_norm                                 !! F(i) = ⟨Δ∂_{b_i}^† ΔH⟩
            end do

            do concurrent (ii = 1:m, i = 1:m, i >= ii) default(none) shared(S_b, O_b, covar_norm, delta, m) local(ind)
                ind = m*(ii-1) - ((ii-2)*(ii-1))/2 + (i-ii) + 1                                  !! Packed index mapping
                S_b(ind) = sum(conjg(O_b(:,i))*O_b(:,ii))*covar_norm                                       !! Covariance
                if (i == ii) S_b(ind) = S_b(ind)%re + delta                           !! Add regularization to diagonals
            end do

            call ppsvx(AP=S_b, b=F_b, x=x_b, uplo='L', fact='E')               !! Stochastic reconfiguration x = S^{-1}F

            self%p_b = beta_1*self%p_b + (1.0_rk - beta_1)*x_b                           !! Biased first moment estimate
            self%r_b = beta_2*self%r_b + (1.0_rk - beta_2)*(x_b**2)                 !! Biased second raw moment estimate
            x_b = ( self%p_b/(1.0_rk - beta_1**epoch) )/sqrt( (self%r_b/(1.0_rk - beta_2**epoch)) + epsilon )    !! ADAM
            self%b = self%b - dtau*x_b                                                           !! Update hidden biases
            !! End Propagate b ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            !! Propagate w ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            do concurrent (j = 1:n, i = 1:m) default(none) shared(O_w, F_w, e_loc, num_samples, covar_norm)
                O_w(:,i,j) = O_w(:,i,j) - sum(O_w(:,i,j))/num_samples               !! Center each column about its mean
                F_w(i,j) = sum(conjg(O_w(:,i,j))*e_loc)*covar_norm                        !! F(i,j) = ⟨Δ∂_{w_{ij}}^† ΔH⟩
            end do

            do concurrent (j = 1:n, ii = 1:m, i = 1:m, i >= ii) default(none) shared(S_w, O_w, covar_norm, delta, m) &
                                                                local(ind)
                ind = m*(ii-1) - ((ii-2)*(ii-1))/2 + (i-ii) + 1                                  !! Packed index mapping
                S_w(ind,j) = sum(conjg(O_w(:,i,j))*O_w(:,ii,j))*covar_norm                                 !! Covariance
                if (i == ii) S_w(ind,j) = S_w(ind,j)%re + delta                       !! Add regularization to diagonals
            end do

            do concurrent (j = 1:n) default(none) shared(S_w, F_w, x_w)
                call ppsvx(AP=S_w(:,j), b=F_w(:,j), x=x_w(:,j), uplo='L', fact='E')   !! Stochastic reconfig x = S^{-1}F
            end do

            self%p_w = beta_1*self%p_w + (1.0_rk - beta_1)*x_w                           !! Biased first moment estimate
            self%r_w = beta_2*self%r_w + (1.0_rk - beta_2)*(x_w**2)                 !! Biased second raw moment estimate
            x_w = ( self%p_w/(1.0_rk - beta_1**epoch) )/sqrt( (self%r_w/(1.0_rk - beta_2**epoch)) + epsilon )    !! ADAM
            self%w = self%w - dtau*x_w                                                                 !! Update weights
            !! End Propagate w ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        end block propagation
    end subroutine propagate

    impure recursive subroutine random_sample(s)
        !---------------------------------------------------------------------------------------------------------------
        !! Subroutine for generating a random sample
        !---------------------------------------------------------------------------------------------------------------
        integer(ik), contiguous, dimension(:), intent(inout) :: s

        real, dimension(size(s)) :: r

        call random_number(r)
        s = nint(r, kind=ik)
    end subroutine random_sample

    pure recursive real(rk) function var(x) result(variance)
        !---------------------------------------------------------------------------------------------------------------
        !! Function for calculating sample variance of a real vector using canonical two-pass algorithm
        !---------------------------------------------------------------------------------------------------------------
        real(rk), contiguous, dimension(:), intent(in) :: x
        variance = sum( (x - sum(x)/size(x))**2 )/(size(x)-1)
    end function var

    pure recursive subroutine get_correlations(samples, corrs, alignment)
        !---------------------------------------------------------------------------------------------------------------
        !! Function for calculating spin-spin correlations of sampled configurations given alignment 'F' or 'A'
        !---------------------------------------------------------------------------------------------------------------
        integer(ik), contiguous, dimension(:,:), intent(inout), target :: samples                       !! Input samples
        real(rk),    contiguous, dimension(:),   intent(out)           :: corrs                   !! Output correlations
        character(len=1), intent(in) :: alignment                                                      !! Spin alignment

        integer(ik), pointer, dimension(:) :: ref_spin, current_spin                              !! Sample row pointers
        integer :: j, n, num_samples, agrees, disagrees                               !! Loop, size, and count variables

        nullify(ref_spin); nullify(current_spin)                                                  !! Initialize pointers
        n = size(samples, dim=2)                                                                  !! Get number of spins
        num_samples = size(samples, dim=1)                                                      !! Get number of samples
        ref_spin => samples(:,n/2+1)                                                        !! Set an odd reference spin
        corrs(n/2+1) = 1.0_rk                                      !! Reference spin is perfectly correlated with itself

        do concurrent (j = 1:n, j /= (n/2+1)) default(none) shared(samples, corrs, alignment, num_samples, ref_spin) &
                                              local(current_spin, agrees, disagrees)
            current_spin => samples(:,j)                                                                    !! j-th spin

            if ( (alignment == 'A') .and. (mod(j,2) == 0) ) then                      !! Count agreements with reference
                agrees = count( (1_ik - current_spin) == ref_spin )
            else
                agrees = count( current_spin == ref_spin )
            end if

            disagrees = num_samples - agrees                                       !! Count disagreements with reference
            corrs(j) = real(agrees - disagrees, kind=rk)/num_samples                           !! Proportional agreement
        end do

        nullify(ref_spin); nullify(current_spin)                                                     !! Nullify pointers
    end subroutine get_correlations

    impure recursive real(rk) function gauss(mu, sig) result(gauss_res)
        !---------------------------------------------------------------------------------------------------------------
        !! Samples random numbers from the standard Normal (Gaussian) Distribution with the given mean and sigma.
        !! Uses the Acceptance-complement ratio from W. Hoermann and G. Derflinger.
        !! This is one of the fastest existing methods for generating normal random variables.
        !!
        !! REFERENCE:  - W. Hoermann and G. Derflinger (1990):
        !!               The ACR Method for generating normal random variables,
        !!               OR Spektrum 12 (1990), 181-185.
        !!
        !! Implementation taken from <https://root.cern.ch/doc/master/TRandom_8cxx_source.html#l00274>
        !! UNURAN (c) 2000  W. Hoermann & J. Leydold, Institut f. Statistik, WU Wien
        !---------------------------------------------------------------------------------------------------------------
        real(rk), intent(in) :: mu, sig

        real(rk) :: kC1, kC2, kC3, kD1, kD2, kD3, kHm, kZm, kHp, kZp, kPhln, kHm1
        real(rk) :: kHp1, kHzm, kHzmp, kAs, kBs, kCs, kB, kX0, kYm, kS, kT
        real(rk) :: rn, x, y, z, res

        kC1   = 1.448242853_rk
        kC2   = 3.307147487_rk
        kC3   = 1.46754004_rk
        kD1   = 1.036467755_rk
        kD2   = 5.295844968_rk
        kD3   = 3.631288474_rk
        kHm   = 0.483941449_rk
        kZm   = 0.107981933_rk
        kHp   = 4.132731354_rk
        kZp   = 18.52161694_rk
        kPhln = 0.4515827053_rk
        kHm1  = 0.516058551_rk
        kHp1  = 3.132731354_rk
        kHzm  = 0.375959516_rk
        kHzmp = 0.591923442_rk

        kAs = 0.8853395638_rk
        kBs = 0.2452635696_rk
        kCs = 0.2770276848_rk
        kB  = 0.5029324303_rk
        kX0 = 0.4571828819_rk
        kYm = 0.187308492_rk
        kS  = 0.7270572718_rk
        kT  = 0.03895759111_rk

        outer: do
            call random_number(y)

            if ( y > kHm1 ) then
                res = kHp*y - kHp1; exit outer
            else if ( y < kZm ) then
                rn = kZp*y - 1.0_rk

                if ( rn > 0.0_rk ) then
                    res = 1.0_rk + rn; exit outer
                else
                    res = -1.0_rk + rn; exit outer
                end if
            else if ( y < kHm ) then
                call random_number(rn)
                rn = rn - 1.0_rk + rn

                if ( rn > 0.0_rk ) then
                    z = 2.0_rk - rn
                else
                    z = -2.0_rk - rn
                end if

                if ( (kC1-y)*(kC3+abs(z)) < kC2 ) then
                    res = z; exit outer
                else
                    x = rn*rn
                    if ( (y+kD1)*(kD3+x) < kD2 ) then
                        res = rn; exit outer
                    else if ( kHzmp-y < exp(-(z*z+kPhln)/2.0_rk) ) then
                        res = z; exit outer
                    else if ( y+kHzm < exp(-(x+kPhln)/2.0_rk) ) then
                        res = rn; exit outer
                    end if
                end if
            end if

            inner: do
                call random_number(x); call random_number(y)
                y = kYm*y
                z = kX0 - kS*x - y

                if ( z > 0.0_rk ) then
                    rn = 2.0_rk + y/x
                else
                    x = 1.0_rk - x
                    y = kYm - y
                    rn = -( 2.0_rk + y/x )
                end if

                if ( (y-kAs+x)*(kCs+x)+kBs < 0.0_rk ) then
                    res = rn; exit inner
                else if ( y < x+kT ) then
                    if ( rn*rn < 4.0_rk*(kB-log(x)) ) then
                        res = rn; exit inner
                    end if
                end if
            end do inner

            exit outer
        end do outer

        gauss_res = res*sig + mu
    end function gauss

end module nnqs
