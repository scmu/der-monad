%if False
\begin{code}
{-# LANGUAGE RankNTypes, FlexibleContexts, ScopedTypeVariables #-}

module LawTranslate where

import Prelude hiding ((>>))
import Control.Monad hiding ((>>))
import Control.Monad.State hiding ((>>))

import ListT  -- use option -i../../code

import Utilities
import Monads
import Queens

(>>) :: Monad m => m a -> m b -> m b
m1 >> m2 = m1 >>= const m2
\end{code}
%endif

\section{Laws and Translation for Global State Monad}
\label{sec:ctxt-trans}

In this section we give a more formal treatment of the non-deterministic global state monad.
Not every implementation of the global state law allows us to accurately
simulate local state semantics though, so we propose additional laws that the
implementation must respect.
These laws turn out to be rather intricate.
To make sure that there exists a model, an implementation is proposed, and it is verified in Coq that the laws and some additional theorems are satisfied.

The ultimate goal, however, is to show the following property:
given a program written for a local-state monad,
if we replace all occurrences of |put| by |putR|, the resulting
program yields the same result when run with a global-state monad.
This allows us to painlessly port our previous algorithm to work
with a global state.
To show this we first introduce a syntax for nondeterministic and stateful
monadic programs and contexts.
Then we imbue these programs with global-state semantics.
Finally we define the function that performs the translation just described, and prove that this translation is correct.



\subsection{Programs and Contexts}
%format hole = "\square"
%format apply z (e) = z "\lbrack" e "\rbrack"
%format <||> = "~\overline{[\!]}~" -- "\mathbin{\scaleobj{0.8}{[\!]\rangle}}"
%format mplusD = "(\overline{[\!]})" 
%format <&> = "\mathbin{\scaleobj{0.8}{\langle\&\rangle}}"
%format <>>=> = "~\overline{\hstretch{0.7}{>\!\!>\!\!=}}~"
%format getD = "\overline{\Varid{get}}"
%format putD =  "\overline{\Varid{put}}"
%format retD = "\overline{\Varid{ret}}"
%format failD = "\overline{\Varid{\varnothing}}"
%format langle = "\scaleobj{0.8}{\langle}"
%format rangle = "\scaleobj{0.8}{\rangle}"
%format emptyListLit = "`[]"
\begin{figure}
\begin{mdframed}
\centering
\scriptsize
\subfloat[]{
\begin{minipage}{0.5\textwidth}
\begin{spec}
data Prog a where
  Return  :: a -> Prog a
  mzero   :: Prog a
  mplus   :: Prog a -> Prog a -> Prog a
  Get     :: (S -> Prog a) -> Prog a
  Put     :: S -> Prog a -> Prog a
\end{spec}
\end{minipage}
}
\subfloat[]{
  \begin{minipage}{0.5\textwidth}
    \begin{spec}
      run     :: Prog a -> Dom a
      retD    :: a -> Dom a
      failD   :: Dom a
      (<||>)  :: Dom a -> Dom a -> Dom a
      getD    :: (S -> Dom a) -> Dom a
      putD    :: S -> Dom a -> Dom a
    \end{spec}
  \end{minipage}
}
\quad
\end{mdframed}
\caption{(a) Syntax for programs. (b) Semantic domain.}
\label{fig:prog-and-dom}
\end{figure}

In the previous sections we have been mixing syntax and semantics,
which we avoid in this section by defining the program syntax as a free monad.
This way we avoid the need for a type-level distinction between programs
with local-state semantics and programs with global-state semantics.
Figure~\ref{fig:prog-and-dom}(a) defines a syntax for
nondeterministic, stateful, closed programs |Prog|, where
the |Get| and |Put| constructors take continuations as arguments, and
the |(>>=)| operator is defined as follows:
\begin{samepage}
\begin{spec}
  (>>=) :: Prog a -> (a -> Prog b) -> Prog b
  Return x       >>= f = f x
  mzero          >>= f = mzero
  (m `mplus` n)  >>= f = (m >>= f) `mplus` (n >>= f)
  Get k          >>= f = Get (\s -> k s >>= f)
  Put s m        >>= f = Put s (m >>= k) {-"~~."-}
\end{spec}
\end{samepage}%
One can see that |(>>=)| is defined as a purely syntactical manipulation, and
its definition has laws \eqref{eq:bind-mplus-dist} and
\eqref{eq:bind-mzero-zero} built-in.

The meaning of such a monadic program is determined by a semantic domain of our
choosing, which we denote with |Dom|, and its corresponding
domain operators |retD|, |failD|, |getD|, |putD| and |(<||||>)|
(see figure~\ref{fig:prog-and-dom}(b)).
The |run :: Prog a -> Dom a| function ``runs'' a program |Prog a| into a value
in the semantic domain |Dom a|:
\begin{samepage}
\begin{spec}
run (Return x)       = retD x
run mzero            = failD
run (m1 `mplus` m2)  = run m1 <||> run m2
run (Get k)          = getD (\s -> run (k s))
run (Put s m)        = putD s (run m) {-"~~."-}
\end{spec}
\end{samepage}%
Note that no |<>>=>| operator is required to define |run|;
in other words, |Dom| need not be a monad.
In fact, as we will see later, we will choose our implementation in such a way
that there does not exist a bind operator for |run|.

\subsection{Laws for Global State Semantics}
\label{sec:model-global-state-sem}
We impose the laws upon |Dom| and the domain operators to ensure the semantics of a
non-backtracking (global-state),
nondeterministic, stateful computation for our programs.
Naturally, we need laws analogous to the state laws and nondeterminism laws to
hold for our semantic domain.
As it is not required that a bind operator
(|(>>=) :: Dom a -> (a -> Dom b) -> Dom b|) be defined for the semantic
domain (and we will later argue that it \emph{cannot} be defined for the domain,
given the laws we impose on it), the state laws
(\eqref{eq:put-put} through \eqref{eq:get-get})
must be reformulated to fit the continuation-passing style of the semantic domain
operators.
\begin{align}
  |putD s (putD t p)| &= |putD t p| \mbox{~~,} \label{eq:put-put-g-d} \\
  |putD s (getD k)| &= |putD s (k s)| \mbox{~~,} \label{eq:put-get-g-d} \\
  |getD (\s -> putD s m)| &= |m| \mbox{~~,} \label{eq:get-put-g-d} \\
  |getD (\s -> getD (\t -> k s t))| &= |getD (\s -> k s s)| \mbox{~~.} \label{eq:get-get-g-d}
\end{align}
Two of the nondeterminism
laws---\eqref{eq:bind-mplus-dist} and
\eqref{eq:bind-mzero-zero}---also mention the bind operator.
As we have seen earlier, they are trivially implied by the definition of |(>>=)|
for |Prog|. Therefore, we need not impose equivalent laws for the semantic
domain (and in fact, we cannot formulate them given the representation we
have chosen).
Only the two remaining nondeterminism
laws---\eqref{eq:mplus-assoc} and \eqref{eq:mzero-mplus}---need to be stated:
%As for the nondeterminism laws
%(\eqref{eq:mplus-assoc}, \eqref{eq:mzero-mplus}, \eqref{eq:bind-mplus-dist},
%\eqref{eq:bind-mzero-zero}),
%we can simply omit the ones that mention at the semantic level |(>>=)|
%as these are proven at the syntactic level: their proof follows immediately
%from |Prog|'s definition of |(>>=)|.
\begin{align}
  &|(m <||||> n) <||||> p| = |m <||||> (n <||||> p)| \mbox{~~,} \\
  &|failD <||||> m| = |m <||||> failD| = |m| \mbox{~~.}
\end{align}
We also reformulate the global-state law~\eqref{eq:put-or}:
\begin{align}
|putD s p <||||> q|        &= |putD s (p <||||> q)| \mbox{~~.}\label{eq:put-or-g-d}
\end{align}
%In Section~\ref{sec:laws-global-state} we also mentioned that a law should exist
%which mandates a limited form of right-distribitivity which only holds on a
%global level.
%The continuation-passing style of our semantic domain operators allows us to
%express a weaker version of this global property (which suffices for our goals)
%as follows:
It turns out that, apart from the {\bf put-or} law,
our proofs require certain additional properties regarding commutativity and
distributivity which we introduce here:
\begin{align}
\begin{split}
|getD (\s -> putD (t s) p <||||> putD (u s) q <||||> putD s failD)| = \\
~~~~~~|getD (\s -> putD (u s) q <||||> putD (t s) p <||||> putD s failD)| \mbox {~~,}
\end{split} \label{eq:put-or-comm-g-d} \\
& |putD s (retD x <||||> p)| = |putD s (retD x) <||||> putD s p| \mbox{~~.}\label{eq:put-ret-or-g-d}
\end{align}
These laws are not considered general ``global state'' laws, because it is
possible to define reasonable implementations of global state semantics that
violate these laws, and because they are not exclusive to global state
semantics.

The |mplusD| operator is not, in general, commutative in a global state setting.
However, we will require that the order in which results are computed does not
matter.
This might seem contradictory at first glance.
To be more precise, we do not require the property
|p <||||> q = q <||||> p| because the subprograms |p| and |q| might perform
non-commuting edits to the global state.
But we do expect that programs without side-effects commute freely;
for instance, we expect |return x <||||> return y = return y <||||> return x|.
In other words, collecting all the results of a nondeterministic computation is
done with a set-based semantics in mind rather than a list-based semantics,
but this does not imply that the order of state effects does not matter.

In fact, the notion of commutativity we wish to impose is still somewhat
stronger than just the fact that results commute: we want the |mplusD| operator
to commute with respect to any pair of subprograms whose modifications of the
state are ignored---that is, immediately overwritten---by the
surrounding program.
This property is expressed by law~\eqref{eq:put-or-comm-g-d}.
The law also implies that the implementation must not record a
history of state changes.

In global-state semantics, |putD| operations cannot, in general,
distribute over |<||||>|.
However, an implementation may permit distributivity if certain conditions are
met.
Law~\eqref{eq:put-ret-or-g-d} states that a |putD| operation distributes over a
nondeterministic choice if the left branch of that choice simply returns a
value.
This law has a particularly striking implication: it disqualifies any
implementation for which a bind operator
|(<>>=>) :: Dom a -> (a -> Dom b) -> Dom b| can be defined!
Consider for instance the following program:
\begin{code}
  putD x (retD w <||> getD retD) <>>=> \z -> putD y (retD z) {-"~~."-}
\end{code}
If \eqref{eq:put-ret-or-g-d} holds, this program should be equal to
\begin{code}
  (putD x (retD w) <||> putD x (getD retD)) <>>=> \z -> putD y (retD z) {-"~~."-}
\end{code}
However, Figure~\ref{fig:put-ret-or-vs-bind} proves that the first program can
be reduced to |putD y (retD w <||||> retD y)|,
whereas the second program is equal to
|putD y (retD w <||||> retD x)|,
which clearly does not always have the same result.

To gain some intuition about why law~\eqref{eq:put-ret-or-g-d} prohibits a bind
operator, consider that the presence or absence of a bind operator influences
what equality of programs means.
Our first intuition might be that we consider two programs equal if they produce
the same outputs given the same inputs. But this is too narrow a view: for
two programs to be considered equal, they must also behave the same under
\emph{composition}; that is, we must be able to replace one for the other within
a larger whole, without changing the meaning of the whole.
The bind operator allows us to compose programs \emph{sequentially}, and
therefore its existence implies that, for two programs to be considered equal,
they must also behave identically under sequential composition.
Under local-state semantics, this additional requirement coincides with other
notions of equality: we can't come up with a pair of
programs which both produce the same outputs given the same inputs, but behave
differently under sequential composition.
But under global-state semantics, we can come up with such counterexamples:
consider the subprograms of our previous example
|putD x (retD w <||||> getD retD)| and
|(putD x (retD w) <||||> putD x (getD retD))|.
Clearly we expect these two programs to produce the exact same results in
isolation, yet when they are sequentially composed with the program
|\z -> putD y (retD z)|, their different nature is revealed (by \eqref{eq:bind-mplus-dist}).

\begin{figure}
  \centering
  \scriptsize
  \subfloat[]{
  \begin{minipage}{0.5\textwidth}
    \begin{code}
      putD x (retD w <||> getD retD) <>>=> \z -> putD y (retD z)
      === {- definition of |(<>>=>)| -}
      putD x (putD y (retD w) <||> getD (\s -> putD y (retD s)))
      === {- by \eqref{eq:put-or-g-d} and \eqref{eq:put-put-g-d} -}
      putD y (retD w <||> getD (\s -> putD y (retD s)))
      === {- by \eqref{eq:put-ret-or-g-d} -}
      putD y (retD w) <||>  putD y (getD (\s -> putD y (retD s)))
      === {- by \eqref{eq:put-get-g-d} and \eqref{eq:put-put-g-d} -}
      putD y (retD w) <||> putD y (retD y)
      === {- by \eqref{eq:put-ret-or-g-d} -}
      putD y (retD w <||> retD y)
    \end{code}
  \end{minipage}
  }
  \subfloat[]{
  \begin{minipage}{0.5\textwidth}
    \begin{code}
      (putD x (retD w) <||> putD x (getD retD))
        <>>=> \z -> putD y (retD z)
      === {- definition of |(<>>=>)| -}
      putD x (putD y (retD w))
        <||> putD x (getD (\s -> putD y (retD s)))
      === {- by \eqref{eq:put-put-g-d} and \eqref{eq:put-get-g-d} -}
      putD y (retD w) <||> putD x (putD y (retD x))
      === {- by \eqref{eq:put-put-g-d} -}
      putD y (retD w) <||> putD y (retD x)
      === {- by \eqref{eq:put-ret-or-g-d} -}
      putD y (retD w <||> retD x)
    \end{code}
  \end{minipage}
  }
  \caption{Proof that law~\eqref{eq:put-ret-or-g-d} implies that a bind operator
    cannot exist for the semantic domain.}
  \label{fig:put-ret-or-vs-bind}
\end{figure}

% put x (return w || q) >>= \z -> put y (return z)
%put x (return w >>= \z -> put y (return z) || get return >>= \z -> put y (return z))
%put x (put y (return w)
%       ||
%       get (\s -> put y (return s))
%      )
%  [put-or]
%put x (put y (return w || get (\s -> put y (return s))))
%  [put-put]
%put y (return w || get (\s -> put y (return s)))
%  [put-ret-or]
%put y (return w) || put y (get \s -> put y (return s))
%  [put-get]
%put y (return w) || put y (put y (return y))
%  [put-put]
%put y (return w) || put y (return y)
%  [put-ret-or]
%put y (return w || return y)
%-> ([(w,y)), (y,y)],y)
%################################################################################
%(put x (return w) || put x (get return))
%>>=
%\z -> put y (return z)
%  [def >>=]
%put x (return w) >>= \z -> put y (return z)
%||
%put x (get return) >>= \z -> put y (return z)
%  [def >>=]
%put x (put y (return w))
%||
%put x (get (\s -> put y (return s)))
%  [put-put, put-get]
%put y (return w)
%||
%put x (put y (return x))
%  [put-put]
%put y (return w)
%||
%put y (return x)
%  [put-or]
%put y (return w || put y return x)
%  [put-ret-or, put-put]
%put y (return w) || put y (return x)
%  [put-ret-or]
%put y (return w || return x)

It is worth remarking that introducing either one of these additional laws
disqualify the example implementation given in
Section~\ref{sec:combining-effects} (even if it is adapted for the
continuation-passing style of these laws).
As the given implementation records the order in which results are yielded by
the computation, law~\eqref{eq:put-or-comm-g-d} cannot be satisfied.
And the example implementation also forms a monad, which means it is incompatible with
law~\eqref{eq:put-ret-or-g-d}.

\paragraph{Machine-Verified Proofs}
From this point forward, we provide proofs mechanized in Coq for many theorems.
When we do, we mark the proven statement with a check mark ($\checkmark$).

\subsection{An Implementation of the Semantic Domain}
\label{sec:GSMonad}
We present an implementation of |Dom| that satisfies the
laws of section \ref{sec:model-global-state-sem}, and we provide
machine-verified proofs to that effect.
In the following implementation, we let |Dom| be the union of |M s a|
for all |a| and for a given |s|.

\begin{samepage}
The implementation is based on a multiset or |Bag| data structure. In the
mechanization, we implement |Bag a| as a function |a -> Nat|.
\begin{code}
type Bag a

singleton  :: a -> Bag a
emptyBag   :: Bag a
sum        :: Bag a -> Bag a -> Bag a
\end{code}
\end{samepage}
\begin{samepage}
We model a stateful, nondeterministic computation with global state semantics as
a function that maps an initial state onto a bag of results, and a final state.
Each result is a pair of the value returned, as well as the state at that point
in the computation.
The use of an unordered data structure to return the results of the computation
is needed to comply with law~\eqref{eq:put-or-comm-g-d}.

In Section~\ref{sec:model-global-state-sem} we mentioned that, as a consequence
of law~\eqref{eq:put-ret-or-g-d} we must design the implementation of our
semantic domain in such a way that it is impossible to define a bind operator
|<>>=> :: Dom a -> (a -> Dom b) -> Dom b| for it.
This is the case for our implementation: we only retain the final result of the
branch without any information on how to continue the branch, which makes it
impossible to define the bind operator.

\begin{code}
type M s a = s -> (Bag (a,s),s)
\end{code}
\end{samepage}
\begin{samepage}
|failD| does not modify the state and produces no results.
|retD| does not modify the state and produces a single result.
\begin{code}
failD :: M s a
failD = \s -> (emptyBag,s)

retD :: a -> M s a
retD x = \s -> (singleton (x,s),s)
\end{code}
\end{samepage}
\begin{samepage}
  |getD| simply passes along the initial state to its continuation.
  |putD| ignores the initial state and calls its continuation with the given
  parameter instead.
\begin{code}
getD :: (s -> M s a) -> M s a
getD k = \s -> k s s

putD :: s -> M s a -> M s a
putD s k = \ _ -> k s
\end{code}
\end{samepage}
\begin{samepage}
The |<||||>| operator runs the left computation with the initial state, then
runs the right computation with the final state of the left computation,
and obtains the final result by merging the two bags of results.
\begin{code}
(<||>) :: M s a -> M s a -> M s a
(xs <||> ys) s =  let  (ansx, s')   = xs s
                       (ansy, s'')  = ys s'
                  in (sum ansx ansy, s'')
\end{code}
\end{samepage}
\begin{lemma}
  This implementation conforms to every law introduced in
  Section~\ref{sec:model-global-state-sem}.~$\checkmark$
\end{lemma}
\subsection{Contextual Equivalence}

\begin{figure}
\begin{mdframed}
  \centering
  \scriptsize
  \subfloat[]{
    \begin{minipage}{0.5\textwidth}
      \begin{spec}
    data Ctx e1 a e2 b where
      hole    :: Ctx e a e a
      COr1    :: Ctx e1 a e2 b -> OProg e2 b
              -> Ctx e1 a e2 b
      COr2    :: OProg e2 b -> Ctx e1 a e2 b
              -> Ctx e1 a e2 b
      CPut    :: (Env e2 -> S) -> Ctx e1 a e2 b
              -> Ctx e1 a e2 b
      CGet    :: (S -> Bool) -> Ctx e1 a (S:e2) b
              -> (S -> OProg e2 b) -> Ctx e1 a e2 b
      CBind1  :: Ctx e1 a e2 b -> (b -> OProg e2 c)
              -> Ctx e1 a e2 c
      CBind2  :: OProg e2 a -> Ctx e1 b (a:e2) c
              -> Ctx e1 b e2 c
  \end{spec}
   \end{minipage}
  }
  \subfloat[]{
    \begin{minipage}{0.5\textwidth}
      \begin{spec}
      data Env (l :: [*]) where
        Nil  :: Env emptyListLit
        Cons :: a -> Env l -> Env (a:l)

      type OProg e a = Env e -> Prog a
      \end{spec}
    \end{minipage}
  }
\end{mdframed}
\caption{(a) Environments and open programs. (b) Syntax for contexts.}
\label{fig:env-and-context}
\end{figure}

\label{subsec:contextual-equivalence}
With our semantic domain sufficiently specified, we can prove analogous
properties for programs interpreted through this domain.
We must take care in how we reformulate these properties however.
It is certainly not sufficient to merely copy the laws as formulated for the
semantic domain, substituting |Prog| data constructors for semantic domain
operators as needed; we must keep in mind that a term in |Prog a| describes a
syntactical structure without ascribing meaning to it.
For example, one cannot simply assert that |Put x (Put y p)| is \emph{equal} to
|Put y p|,
because although these two programs have the same semantics, they
are not structurally identical.
It is clear that we must define a notion of ``semantic equivalence'' between
programs.
We can map the syntactical structures in |Prog a| onto the semantic domain
|Dom a| using |run| to achieve that.
Yet wrapping both sides of an equation in |run| applications
is not enough as such statements only apply at the top-level of a program.
For instance, while |run (Put x (Put y p)) = run (Put y p)| is a correct statement,
we cannot prove
|run (Return w `mplus` Put x (Put y p)) = run (Return w `mplus` Put y p)|
from such a law.

So the concept of semantic equivalence in itself is not sufficient; we require
a notion of ``contextual semantic equivalence'' of programs which allows us to
formulate properties about semantic equivalence which hold in any surrounding
context.
Figure~\ref{fig:env-and-context}(a) provides the definition for single-hole
contexts |Ctx|.
A context |C| of type |Ctx e1 a e2 b| can be interpreted as a function that, given a
program that returns a value of type |a| under environment |e1| (in other words:
the type and environment of the hole), produces a program that returns a value
of type |b| under environment |e2| (the type and environment of the whole program).
Filling the hole with |p| is denoted by |apply C p|.
The type of environments, |Env| is defined using heterogeneous lists
(Figure~\ref{fig:env-and-context}(b)).
When we consider the notion of programs in contexts, we must take into account
that these contexts may introduce variables which are referenced by the program.
The |Prog| datatype however represents only closed programs.
Figure~\ref{fig:env-and-context}(b) introduces the |OProg| type to represent
``open'' programs, and the |Env| type to represent environments.
|OProg e a| is defined as the type of functions that construct a \emph{closed}
program of type |Prog a|, given an environment of type |Env e|.
Environments, in turn, are defined as heterogeneous lists.
We also define a function for mapping open programs onto the semantic domain.
\begin{spec}
  orun :: OProg e a -> Env e -> Dom a
  orun p env = run (p env) {-"~~."-}
\end{spec}

We can then assert that two programs are contextually equivalent if, for
\emph{any} context, running both programs wrapped in that context will
yield the same result:
\newcommand{\CEq}{=_\mathtt{GS}}
\begin{align*}
  |m1| \CEq |m2| \triangleq \forall |C|. |orun (apply C m1)| = |orun (apply C m2)| \mbox{~~.}
\end{align*}

We can then straightforwardly formulate variants of the state laws, the
nondeterminism laws and the |put|-|or| law for this global state monad as
lemmas. For example, we reformulate law~\eqref{eq:put-put-g-d} as
\begin{align*}
  |Put s (Put t p)| &\CEq |Put t p| \mbox{~~.}
\end{align*}
Proofs for the state laws, the nondeterminism laws and the |put|-|or| law then
easily follow from the analogous semantic domain laws.

More care is required when we want to adapt law~\eqref{eq:put-ret-or-g-d}
into the |Prog| setting. At the end of Section~
\ref{sec:model-global-state-sem}, we saw that this law precludes the existence
of a bind operator in the semantic domain.
Since a bind operator for |Prog|s exists, it might seem we're out of luck when
we want to adapt law~\eqref{eq:put-ret-or-g-d} to |Prog|s.
But because |Prog|s are merely syntax, we have much more fine-grained control
over what equality of programs means.
When talking about the semantic domain, we only had one notion of equality: two
programs are equal only when one can be substituted for the other in any
context. So if, in that setting, we want to introduce a law that does not hold
under a particular composition (in this case, sequential composition), the only
way we can express that is to say that that composition is impossible in the
domain.
But the fact that |Prog| is defined purely syntactically opens up the
possibility of defining multiple notions of equality which may exist at the same
time. In fact, we have already introduced syntactic equality, semantic equality, and
contextual equality. It is precisely this choice of granularity that allows us
to introduce laws which only hold in programs of a certain form (non-contextual
laws), while other laws are much more general (contextual laws). A direct
adaptation of law~\eqref{eq:put-ret-or-g-d} would look something like this:
\begin{align*}
  \forall |C|.~ |C| \text{ is bind-free} \Rightarrow &|orun (apply C (Put s (Return x `mplus` p)))| \\
  = &|orun (apply C (Put s (Return x) `mplus` Put s p))| \mbox{~~.}
\end{align*}
In other words, the two sides of the equation can be substituted for one
another, but only in contexts which do not contain any binds.
However, in our mechanization, we only prove a more restricted version where
the context must be empty (in other words, what we called semantic equivalence),
which turns out to be enough for our purposes.
\begin{align}
  |run (Put s (Return x `mplus` p))| = |run (Put s (Return x) `mplus` Put s p)| \mbox{~~.} \label{eq:put-ret-or-g} \checkmark
\end{align}

% The formulation of a
% |put|-|ret|-|or| law-like property \eqref{eq:put-ret-or-g-d} requires somewhat
% more care: because there exists a bind operator for |Prog|, we must stipulate
% that it does not hold in arbitrary contexts:
% \begin{align}
% |run (Put s (Return x `mplus` p))| = |run (Put s (Return x) `mplus` Put s p)|
% \end{align}

\subsection{Simulating Local-State Semantics}

We simulate local-state semantics by replacing each occurrence of |Put| by a
variant that restores the state, as described in Section~\ref{subsec:state-restoring-ops}. This transformation is implemented by the
function |trans| for closed programs, and |otrans| for open programs:
\begin{samepage}
\begin{spec}
  trans   :: Prog a -> Prog a
  trans (Return x)     = Return x
  trans (p `mplus` q)  = trans p `mplus` trans q
  trans mzero          = mzero
  trans (Get p)        = Get (\s -> trans (p s))
  trans (Put s p)      = Get (\s' -> Put s (trans p) `mplus` Put s' mzero) {-"~~,"-}

  otrans  :: OProg e a -> OProg e a
  otrans p             = \env -> trans (p env) {-"~~."-}
\end{spec}
\end{samepage}%
We then define the function |eval|, which runs a transformed program (in other
words, it runs a program with local-state semantics).
\begin{spec}
eval :: Prog a -> Dom a
eval = run . trans {-"~~."-}
\end{spec}
We show that the transformation works by proving that our free monad equipped
with |eval| is a correct
implementation for a nondeterministic, stateful monad with local-state semantics.
We introduce notation for ``contextual equivalence under simulated backtracking
semantics'':
\newcommand{\CEqLS}{=_\mathtt{LS}}
\begin{align*}
  |m1| \CEqLS |m2| \triangleq \forall |C|. |eval (apply C m1)| = |eval (apply C m2)| \mbox{~~.}
\end{align*}
For example, we formulate the statement that the |put|-|put|
law~\eqref{eq:put-put-g-d} holds for our monad as interpreted by |eval| as
\begin{align*}
  |Put s (Put t p)| &\CEqLS |Put t p| \mbox{~~.} \checkmark
\end{align*}
Proofs for the nondeterminism laws follow trivially from the nondeterminism laws
for global state.
The state laws are proven by promoting |trans| inside, then applying
global-state laws.
For the proof of the |get|-|put| law, we require the property that in
global-state semantics, |Put| distributes over |(`mplus`)| if the left branch
has been transformed (in which case the left branch leaves the state unmodified).
This property only holds at the top-level.
\begin{align}
  % put_or_trans
|run (Put x (trans m1 `mplus` m2))| = |run (Put x (trans m1) `mplus` Put x m2)| \label{eq:put-ret-mplus-g}\mbox{~~.} \checkmark
\end{align}
Proof of this lemma depends on law~\eqref{eq:put-ret-or-g-d}.

Finally, we arrive at the core of our proof:
to show that the interaction of state and nondeterminism in this
implementation produces backtracking semantics.
To this end we prove laws analogous to the local state laws
\eqref{eq:mplus-bind-dist} and \eqref{eq:mzero-bind-zero}
\begin{align}
  |m >> mzero|                      &\CEqLS |mzero| \mbox{~~,} \label{eq:mplus-bind-zero-l} \checkmark \\
  |m >>= (\x -> f1 x `mplus` f2 x)| &\CEqLS |(m >>= f1) `mplus` (m >>= f2)| \mbox{~~.} \checkmark \label{eq:mplus-bind-dist-l}
\end{align}
We provide machine-verified proofs for these theorems.
The proof for~\eqref{eq:mplus-bind-zero-l} follows by straightforward induction.
The inductive proof (with induction on |m|) of law~\eqref{eq:mplus-bind-dist-l}
requires some additional lemmas.

For the case |m = m1 `mplus` m2|, we require the property that, at the top-level
of a global-state program, |mplus| is commutative if both its operands are
state-restoring.
Formally:
\begin{align}
  |run (trans p `mplus` trans q)| = |run (trans q `mplus` trans p)|\mbox{~~.} \checkmark
\end{align}
The proof of this property motivated the introduction of
law~\eqref{eq:put-or-comm-g-d}.

The proof for both the |m = Get k| and |m = Put s m'| cases requires that |Get|
distributes
over |mplus| at the top-level of a global-state program if the left branch is
state restoring.
\begin{align}
  % get_or_trans
|run (Get (\s -> trans (m1 s) `mplus` (m2 s)))| = \\
|run (Get (\s -> trans (m1 s)) `mplus` Get m2)| \label{eq:get-ret-mplus-g}\mbox{~~.} \checkmark
\end{align}

And finally, we require that the |trans| function is, semantically speaking,
idempotent, to prove the case |m = Put s m'|.
\begin{align}
  % get_or_trans
|run (trans (trans p)) = run (trans p)| \label{eq:run-trans-trans} \mbox{~~.} \checkmark
\end{align}

\noindent

\subsection{Backtracking with a Global State Monad}
\label{sec:backtrack-gs}
Although we can now interpret a local state program through translation to a
global state program, we have not quite yet delivered on our promise to address
the space usage issue of local state semantics.
From the definition of |putR| it is clear that we simply make the implicit
copying of the local state semantics explicit in the global state semantics.
As mentioned in Section~\ref{sec:chaining}, rather than using |put|, some
algorithms typically use a pair of commands |modify next| and |modify prev|,
with |prev . next = id|, to respectively update and roll back the state.
This is especially true when the state is implemented using an array or other data structure that is usually not overwritten in its entirety.
Following a style similar to |putR|, this can be modelled by:
\begin{spec}
  modifyR :: MStateNondet s m => (s -> s) -> (s -> s) -> m ()
  modifyR next prev = modify next `mplus` side (modify prev) {-"~~."-}
\end{spec}
Unlike |putR|, |modifyR| does not keep any copies of the old state alive,
as it does not introduce a branching point where the right branch refers to a
variable introduced outside the branching point.
Is it safe to use an alternative translation, where the pattern
|get >>= (\s -> put (next s) >> m)| is not translated into
|get >>= (\s -> putR (next s) >> trans m)|, but rather into
|modifyR next prev >> trans m|?
We explore this question by extending our |Prog| syntax with an additional
|ModifyR| construct, thus obtaining a new |ProgM| syntax:
\begin{spec}
data ProgM a where
...
  ModifyR  :: (S -> S) -> (S -> S) -> ProgM a -> ProgM a
\end{spec}

We assume that |prev . next = id| for every |ModifyR next prev p| in a |ProgM a| program.

We then define two translation functions from |ProgM a| to |Prog a|,
which both replace |Put|s with |putR|s along the way, like the regular
|trans| function.
The first replaces each |ModifyR| in the program by a direct analogue of the
definition given above, while the second replaces it by
|Get (\s -> Put (next s) (trans_2 p))|:

\begin{spec}
   trans_1 :: ProgM a -> Prog a
   ...
   trans_1 (ModifyR next prev p)  =        Get (\s -> Put (next s) (trans_1 p)
                                   `mplus`  Get (\t -> Put (prev t) mzero))


   trans_2 :: ProgM a -> Prog a
   ...
   trans_2 (ModifyR next prev p)  = Get (\s -> putR (next s) (trans_2 p))
     where putR s p = Get (\t -> Put s p `mplus` Put t mzero)
\end{spec}

It is clear that |trans_2 p| is the exact same program as |trans p'|, where |p'|
is |p| but with each |ModifyR next prev p| replaced by |Get (\s -> Put (next s) p)|.

We then prove that these two transformations lead to semantically identical
instances of |Prog a|.
\begin{lemma}
  |run (trans_1 p) = run (trans_2 p)|. \checkmark
\end{lemma}
This means that, if we make some effort to rewrite parts of our program to use
the |ModifyR| construct rather than |Put|, we can use the more efficient
translation scheme |trans_1| to avoid introducing unnecessary copies.

%\begin{align*}
%  |eval (apply C (Get (\s -> Put (next s) m)))|
%  =
%  |run (apply (transC C) (modifyR next prev (trans m)))| \mbox{~~.}
%\end{align*}


%\begin{spec}
%modifyR :: {N, S s} `sse` eps -> (s -> s) -> (s -> s) -> Me eps ()
%modifyR next prev = modify next `mplus` side (modify prev) {-"~~."-}
%\end{spec}
%%if False
%\begin{code}
%modifyR :: (MonadPlus m, MonadState s m) => (s -> s) -> (s -> s) -> m ()
%modifyR next prev =  modify next `mplus` side (modify prev) {-"~~,"-}
%\end{code}
%%endif
%One can see that |modifyR next prev >> m| expands to
%|(modify next >> m) `mplus` side (modify prev)|, thus the two |modify|s are performed before and after |m|.
%
%Assume that |s0| is the current state.
%Is it safe to replace |putR (next s0) >> m| by |modifyR next prev >> m|?
%We can do so if we are sure that |m| always restores the state to |s0| before |modify prev| is performed.
%We say that a monadic program |m| is {\em state-restoring} if, for all |comp|, the initial state in which |m >>= comp| is run is always restored when the computation finishes. Formally, it can be written as:
%\begin{definition} |m :: {N, S s} `sse` eps => Me eps a| is called {\em state-restoring} if
%  |m = get >>= \s0 -> m `mplus` side (put s0)|.
%\end{definition}
%Certainly, |putR s| is state-restoring. In fact, the following properties allow state-restoring programs to be built compositionally:
%\begin{lemma} We have that
%\begin{enumerate}
%\item |mzero| is state-restoring,
%\item |putR s| is state-restoring,
%\item |guard p >> m| is state-restoring if |m| is,
%\item |get >>= f| is state-restoring if |f x| is state-storing for all |x|, and
%\item |m >>= f| is state restoring if |m| is state-restoring.
%\end{enumerate}
%\end{lemma}
%\noindent Proof of these properties are routine exercises.
%With these properties, we also have that, for a program |m| written using our program syntax, |trans m| is always state-restoring.
%The following lemma then allows us to replace certain |putR| by |modifyR|:
%\begin{lemma} Let |next| and |prev| be such that |prev . next = id|.
%If |m| is state-restoring, we have
%%if False
%\begin{code}
%putRSRModifyR ::
%  (MonadPlus m, MonadState s m) => (s -> s) -> (s -> s) -> m b -> m b
%putRSRModifyR next prev m =
%\end{code}
%\begin{code}
%  get >>= \s -> putR (next s) >> m {-"~~"-}=== {-"~~"-}
%    modifyR next prev >> m {-"~~."-}
%\end{code}
%%endif
%\begin{equation*}
%  |get >>= \s -> putR (next s) >> m| ~=~
%    |modifyR next prev >> m| \mbox{~~.}
%\end{equation*}
%\end{lemma}

% \paragraph{Backtracking using a global-state monad}
% Recall that, in Section~\ref{sec:solve-n-queens},
% we showed that a problem formulated by |unfoldM p f z >>= assert (all ok . scanlp oplus st)| can be solved by a hylomorphism |solve p f ok oplus st z|,
% run in a non-deterministic local-state monad.
% Putting all the information in this section together,
% we conclude that solutions of the same problem can be computed,
% in a non-deterministic global-state monad,
% by |run (solveR p f ok oplus ominus st z)|, where |(`ominus` x) . (`oplus` x) = id| for all |x|, and |solveR| is defined by:
% \begin{spec}
% solveR :: {N, S s} `sse` eps =>  (b -> Bool) -> (b -> Me eps (a, b)) ->
%                                  (s -> Bool) -> (s -> a -> s) -> (s -> a -> s) ->
%                                  s -> b -> Me eps [a]
% solveR p f ok oplus ominus st z = putR st >> hyloM odot (return []) p f z
%   where x `odot` m =  (get >>= guard . ok . (`oplus` x)) >>
%                       modifyR (`oplus` x) (`ominus` x) >> ((x:) <$> m) {-"~~."-}
% \end{spec}
% Note that the use of |run| enforces that the program is run as a whole, that is, it cannot be further composed with other monadic programs.



\paragraph{|n|-Queens using a global state}
To wrap up, we revisit the |n|-queens puzzle.
Recall that, for the puzzle, the operator that alters the state (to check whether a chess placement is safe) is defined by
\begin{spec}
(i,us,ds) `oplus` x = (1 + i,  (i+x):us,  (i-x):ds) {-"~~."-}
\end{spec}
By defining |(i,us,ds) `ominus` x  = (i - 1, tail us, tail ds)|,
we have |(`ominus` x) . (`oplus` x) = id|.
One may thus compute all solutions to the puzzle,
in a scenario with a shared global state, by |run (queensR n)|, where
\begin{spec}
queensR n = put (0,[],[]) >> qBody [0..n-1] {-"~~,"-}

qBody []  =  return []
qBody xs  =  select xs >>= \(x,ys) ->
             (get >>= (guard . ok . (`oplus` x))) >>
             modifyR (`oplus` x) (`ominus` x) >> ((x:) <$> qBody ys) {-"~~,"-}
  where  (i,us,ds) `oplus` x   = (1 + i,  (i+x):us,  (i-x): ds)
         (i,us,ds) `ominus` x  = (i - 1,  tail us,   tail ds)
         ok (_,u:us,d:ds) = (u `notElem` us) && (d `notElem` ds) {-"~~."-}
\end{spec}

% \delete{
% \paragraph{Properties} In absence of \eqref{eq:mplus-bind-dist} and \eqref{eq:mzero-bind-zero}, we instead assume the following properties.
% \begin{align}
%   |side m1 `mplus` side m2| &= |side (m1 >> m2)| \mbox{~~,}
%     \label{eq:side-side} \\
%   |put s >> (m1 `mplus` m2)| &= |(put s >> m1) `mplus` m2| \mbox{~~,}
%     \label{eq:put-mplus}\\
%   |get >>= (\x -> f x `mplus` m)| &=~ |(get >>= f) `mplus` m| \mbox{~~, |x| not free in |m|,}
%       \label{eq:get-mplus}\\
%   |(put s >> return x) `mplus`  m| &= |return x `mplus` (put s >> m)| ~~\mbox{,}
%       \label{eq:put-ret-side}\\
%   |side m `mplus` n| &=~ |n `mplus` side m| \mbox{~~, for |m :: Me N a|.}
%         \label{eq:side-nd-mplus}
% \end{align}
% %if False
% \begin{code}
% propSideSide m1 m2 = (side m1 `mplus` side m2) === side (m1 >> m2)
% propPutMPlus s m1 m2 = (put s >> (m1 `mplus` m2)) === ((put s >> m1) `mplus` m2)
% propGetMPlus f m = (get >>= (\x -> f x `mplus` m)) === ((get >>= f) `mplus` m)
% propPutRetSide s x m = ((put s >> return x) `mplus`  m) === (return x `mplus` (put s >> m))
% propSideNdMPlus m n = (side m `mplus` n) === (n `mplus` side m)
% \end{code}
% %endif
% They all show the sequential nature of |mplus| in this setting: in \eqref{eq:side-side}, adjacent |side| commands can be combined; in \eqref{eq:put-mplus} and \eqref{eq:get-mplus}, state operators bound before |mplus| branches can be bound to the leftmost branch, and in \eqref{eq:put-ret-side}, the effect of |put s >> return x| can be moved to the next branch. Finally, \eqref{eq:side-nd-mplus} allows side effects to commute with branches that only returns non-deterministic results.
% By \eqref{eq:side-side} we have
% \begin{equation}
%  |side (put s) `mplus` side (put t) = side (put t)| \mbox{~~.}
%   \label{eq:side-put-put}
% \end{equation}
% While we do not have right-distributivity in general, we may still assume distributivity for specific cases:
% \begin{align}
%  |get >>= \s -> f1 s `mplus` f2 s| &=~ |(get >>= f1) `mplus` (get >>= f2)| \mbox{~~, if |f1 s :: Me N a|}
%     \label{eq:get-mplus-distr}\\
%  |get >>= \s -> f1 s `mplus` f2 s| &=~ |(get >>= (\s -> f1 s `mplus` side (put s))) `mplus` (get >>= f2)| \mbox{~~.}
%       \label{eq:get-mplus-side-distr}
% \end{align}
% %if False
% \begin{code}
% propGetMPlusDistr f1 f2 = (get >>= \x -> f1 x `mplus` f2 x) === ((get >>= f1) `mplus` (get >>= f2))
% propGetMPlusSideDistr f1 f2 = (get >>= \x -> f1 x `mplus` f2 x) === ((get >>= (\x -> f1 x `mplus` side (put x))) `mplus` (get >>= f2))
% \end{code}
% %endif
% Property \eqref{eq:get-mplus-distr} allows right-distributivity of |get| if the branches are only non-deterministic.
% It helps to prove that |get| commutes with non-determinism.
% In general cases, we need a |side (put x)| in the first branch to ensure that the second branch gets the correct value, as in \eqref{eq:get-mplus-side-distr}.
% } %delete
%
%
% \delete{
% \subsection{State-Restoring Programs}
% \label{sec:state-restoring}
%
% In this section we present an interesting programming pattern that exploits left-distributivity \eqref{eq:bind-mplus-dist}.
% Define the following variation of |put|:%
% \footnote{The author owes the idea of |putR| to Tom Schrijvers. See Section \ref{sec:conclusion} for more details.}
%
% \begin{lemma}\label{lma:putR-basics}
% The following laws regarding |putR| are true:
% \begin{align*}
%     |putR s >>= get| ~&=~ |putR s >>= return s| \mbox{~~,} \\
%     |putR s >> putR s'| ~&=~ |putR s'|  \mbox{~~.}
% \end{align*}
% \end{lemma}
%
% \begin{lemma}\label{lma:putR-nd-commute}
% |putR| commutes with non-determinism. That is, |m >>= \x -> putR s >> return x = putR s >> m| for |m :: Me N a|.
% \end{lemma}
%
% Proof of Lemma \ref{lma:putR-basics} is a routine exercise. Lemma \ref{lma:putR-nd-commute} can be proved by induction on the syntax of |m|, using properties including \eqref{eq:side-side}, \eqref{eq:put-ret-side}, \eqref{eq:side-nd-mplus}, and \eqref{eq:get-mplus-side-distr}.
%
% % \begin{proof}
% % We present the proof for the |putR|-|putR| law for illustrative purpose. The proof demonstrates the use of \eqref{eq:put-mplus} and \eqref{eq:side-put-put}.
% % \begin{spec}
% %    putR s >> putR s'
% % =  (get >>= \s0 -> (put s `mplus` side (put s0))) >>
% %    (get >>= \s0 -> (put s' `mplus` side (put s0)))
% % =    {- left-distributivity \eqref{eq:bind-mplus-dist} -}
% %    get >>= \s0 -> (put s >> get >>= \s0 -> (put s' `mplus` side (put s0))) `mplus` side (put s0)
% % =    {- |put|-|get| \eqref{eq:get-put} -}
% %    get >>= \s0 -> (put s >> (put s' `mplus` side (put s))) `mplus` side (put s0)
% % =    {- by \eqref{eq:put-mplus} -}
% %    get >>= \s0 -> (put s >> puts') `mplus` side (put s) `mplus` side (put s0)
% % =    {- |put|-|put| \eqref{eq:put-put} and \eqref{eq:side-put-put} -}
% %    get >>= \s0 -> put s' `mplus` side (put s0)
% % =  putR s' {-"~~."-}
% % \end{spec}
% % \end{proof}
% Note that we do not have a |get|-|putR| law: |get >>= putR| does not equal |return ()|. To see that, observe that |(get >>= putR) >> put t| terminates with the initial state, while |return () >> put t| terminates with state |t|.
%
% \paragraph{State-Restoration, Compositionally} Pushing the idea a bit further, we say that a monadic program |m| is {\em state-restoring} if, for all |comp|, the initial state in which |m >>= comp| is run is always restored when the computation finishes. Formally, it can be written as:
% \begin{definition} |m :: {N, S s} `sse` eps => Me eps a| is called {\em state-restoring} if
%   |m = get >>= \s0 -> m `mplus` side (put s0)|.
% \end{definition}
% Certainly, |putR s| is state-restoring. In fact, state-restoring programs can be built compositionally, using the following properties:
% \begin{lemma} We have that
% \begin{enumerate}
% \item |mzero| is state-restoring,
% \item |putR s| is state-restoring,
% \item |guard p >> m| is state-restoring if |m| is,
% \item |get >>= f| is state-restoring if |f x| is state-storing for all |x|, and
% \item |m >>= f| is state restoring if |m| is state-restoring.
% \end{enumerate}
% \end{lemma}
% Proof of these properties are routine exercises.
%
% \paragraph{Incremental Updating and Restoration}
% Identifying state-restoring programs helps to discover when we can update and restore the state in an incremental manner.
% When the state |s| is a big structure, such as an array, it might not be feasible to perform |put s| that rewrites an entire array.
% Instead one might use another command |modify f| that applies the function |f| to the state. It can be characterised by:
% \begin{spec}
%   modify f = get >>= \s -> put (f s) {-"~~,"-}
% \end{spec}
% but one may assume that, for commands such as |modify (\arr -> arr // [(i,x)])| (where |(// [(i,x)])| updates the |i|-th entry of the array to |x|), there exists a quicker implementation that mutates the array rather than creating a new array.
%
% Given a function |next :: s -> s| that alters the state, and |prev :: s -> s| that is the inverse of |next|, we define the following state-restoring variation of |modify|:
% \begin{spec}
% modifyR :: {N, S s} `sse` eps -> (s -> s) -> (s -> s) -> Me eps ()
% modifyR next prev =  modify next `mplus` side (modify prev) {-"~~,"-}
% \end{spec}
% %if False
% \begin{code}
% modifyR :: (MonadPlus m, MonadState s m) => (s -> s) -> (s -> s) -> m ()
% modifyR next prev =  modify next `mplus` side (modify prev) {-"~~,"-}
% \end{code}
% %endif
% such that |modifyR next prev >> comp| performs |modify next| before computation in |comp|, and |modify prev| afterwards. We have that:
% \begin{lemma} Let |next| and |prev| be such that |prev . next = id|.
% If |m| is state-restoring, we have
% %if False
% \begin{code}
% putRSRModifyR ::
%   (MonadPlus m, MonadState s m) => (s -> s) -> (s -> s) -> m b -> m b
% putRSRModifyR next prev m =
% \end{code}
% %endif
% \begin{code}
%   get >>= \s -> putR (next s) >> m {-"~~"-}=== {-"~~"-}
%     modifyR next prev >> m {-"~~."-}
% \end{code}
% \end{lemma}
% We look at its proof, which demonstrates the use of \eqref{eq:side-side} -- \eqref{eq:get-mplus}, monad laws, and laws regarding |get| and |put|.
% For the rest of this paper we use the following abbreviations:
% \begin{code}
% sidePut st  = side (put st)    {-"~~,"-}
% sideMod f   = side (modify f)  {-"~~."-}
% \end{code}
% \begin{proof} We calculate:
% %if False
% \begin{code}
% putRSRModifyRDer1 ::
%   (MonadPlus m, MonadState s m) => (s -> s) -> (s -> s) -> m b -> m b
% putRSRModifyRDer1 next prev m =
% \end{code}
% %endif
% \begin{code}
%       modifyR next prev >> m
%  ===    {- definiton of |modifyR|, |modify|, and left-distributivity \eqref{eq:bind-mplus-dist} -}
%       (get >>= \s -> put (next s) >> m) `mplus` sideMod prev
%  ===    {- by \eqref{eq:get-mplus} -}
%       get >>= \s -> (put (next s) >> m) `mplus` sideMod prev {-"~~."-}
% \end{code}
% We focus on the part within |(get >>= \s -> _)|:
% %if False
% \begin{code}
% putRSRModifyRDer2 ::
%   (MonadPlus m, MonadState s m) =>
%   (s -> s) -> (s -> s) -> s -> m a -> m a
% putRSRModifyRDer2 next prev s m =
% \end{code}
% %endif
% \begin{code}
%       (put (next s) >> m) `mplus` sideMod prev
%  ===    {- |m| state-restoring -}
%       (put (next s) >> get >>= \s' -> m `mplus` sidePut s') `mplus` sideMod prev
%  ===    {- |put|-|get| \eqref{eq:get-put} -}
%       (put (next s) >> (m `mplus` sidePut (next s))) `mplus` sideMod prev
%  ===    {- by \eqref{eq:put-mplus} -}
%       put (next s) >> (m `mplus` sidePut (next s) `mplus` sideMod prev)
%  ===    {- by \eqref{eq:side-side}, and |prev . next = id| -}
%       put (next s) >> (m `mplus` sidePut s)
%  ===    {- by \eqref{eq:put-mplus} -}
%       (put (next s) >> m) `mplus` sidePut s {-"~~."-}
% \end{code}
% Put it back to the context |(get >>= \s -> _)|, and the expression simplifies to |get >>= \s -> putR (next s) >> m|.
% \end{proof}
%
% } %delete
