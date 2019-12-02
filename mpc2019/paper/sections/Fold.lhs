\section{Proving the $\mathit{put}_{\text{R}}$ Transformation Correct For a Given Implementation}
Before we tackle the general proof of correctness of the |putR| transformation
correct, we dip our toes into something a bit more straightforward: showing that
the transformation is correct for specific implementations of global and local
state. This lets us use a somewhat more concrete setting to introduce some
infrastructure needed for the more general proof, as well as demonstrate a case
study of a fold fusion proof (TODO: citation), a technique that is interesting
in its own right.

In the previous sections we have been mixing syntax and semantics,
which we avoid in this section by defining the program syntax as a free monad.
This way we avoid the need for a type-level distinction between programs
with local-state semantics and programs with global-state semantics.
The state and nondeterminism interfaces are then provided as ``algebras''.

\subsection{Composing Handlers}
\begin{code}
  data Free f a where
    Ret :: a             -> Free f a
    Op  :: f (Free f a)  -> Free f a

  data StateF a where
    Get :: (S -> a)  -> StateF a
    Put :: S -> a    -> StateF a
    deriving Functor

  data NondetF a where
    mzero :: NondetF a
    mplus :: NondetF a -> NondetF a -> NondetF a
    deriving Functor
\end{code}
The type |Free StateF a| then represents stateful computations, and similarly the
type |Free NondetF a| represents nondeterministic computations. Computations with
multiple effects can be typed with a sum type |(+)| over types of kind |* -> *|. 
\begin{code}
  data (f + g) a where
    Inl :: f a -> (f + g) a
    Inr :: g a -> (f + g) a
    deriving Functor
\end{code}
The type for programs we defined earlier, |Prog|, is then isomorphic to
|Free (StateF + NondetF)|.
The |(+)| type is morally commutative, associative, and has a zero element
(TODO: folds haven't been introduced yet!):
\begin{code}
comm :: (Functor f, Functor g) => Free (f :+: g) a -> Free (g :+: f) a
comm = fold Val alg
  where alg (Inl f) = Op (Inr f)
        alg (Inr g) = Op (Inl g)

assocl :: (Functor f, Functor g, Functor h)
       => Free (f + (g + h)) a -> Free ((f + g) + h) a
assocl = fold Val alg
  where  alg (Inl f)        = Op (Inl (Inl f))
         alg (Inr (Inl g))  = Op (Inl (Inr g))
         alg (Inr (Inr h))  = Op (Inr h)

assocr :: (Functor f, Functor g, Functor h)
       => Free ((f + g) + h) a -> Free (f + (g + h)) a
assocr = fold Val alg
  where  alg (Inl (Inl f))  = Op (Inl f)
         alg (Inl (Inr g))  = Op (Inr (Inl g))
         alg (Inr h)        = Op (Inr (Inr h))

data Nil a deriving Functor

hNil :: Free Nil a -> a
hNil (Val x) = x
-- other cases cannot occur
\end{code}

\paragraph{Composing Handlers.}
A strength of the |Free|-based encoding is that we can not only write programs
with effect sets composed from smaller effect sets, we can also write the {\em
handlers} for these effect sets compositionally.
The type of a compositional handler indicates that it handles one effect of the
effect set of the program, yielding a new effectful program where the effect set
contains all the remaining effects. The types for compositional state and
nondeterminism handlers can be written as (TODO give some intuition how to come
up with these?):
\begin{code}
hState   :: Functor f => Free (StateF   + f) a -> (S -> Free f (a,S))
hNondet  :: Functor f => Free (NondetF  + f) a -> Free f [a]
\end{code}
This is a bit reminiscent of a ``linked list'' of effects. Like a linked list, a
``nil'' element is needed to terminate the list; this is provided to us by the
|Nil| type.

For instance, we can compose a handler for local state semantics out of the
``atomic'' handlers for state and nondeterminism.
\begin{code}
hLocal :: Free (StateF + (NondetF + Nil)) a
hLocal = fmap (hNil . hNondet) . hState  
\end{code}
In other words, local state semantics is the semantics where we
nondeterministically choose between different stateful computations (TODO
connect this more explicitly to our intuition of local state semantics?).
Later on, we shall prove that this composition forms a valid implementation of
local state semantics. TODO

Global state semantics can be implemented by simply inverting the order of the
handlers: rather than nondeterministically choosing between stateful
computations as local state does, in global state semantics we'll run a
state through a nondeterministic computation.
\begin{code}
hGlobal :: Free (NondetF + (StateF + Nil)) a
hGlobal = fmap hNil . hState . hNondet
\end{code}
Note that, because nondeterminism has to be handled first, we also changed 
the type of our program from |Free (StateF + (NondetF + Nil)) a| to
|Free (NondetF + (StateF + Nil)) a|. If we want |hGlobal| to operate on the same
type of programs as |hLocal|, we need to introduce some additional type
gymnastics.
\begin{code}
hGlobal' :: Free (StateF + (NondetF + Nil)) a
hGlobal' = fmap hNil . hState . comm . hNondet . assocr . comm
\end{code}

\paragraph{Notational Conventions.}
To avoid getting bogged down in this level of technical detail, we introduce some
simplifications. From this point onwards, we assume that the type constructor
|(+)| is implicitly commutative and associative, and has |Nil| as a zero
element; for example, we treat the type
|Free (f + g + Nil) a| as the same type as |Free (g + f) a|, without explicitly
converting between them. We also omit the |Inr| and |Inl| constructors from our
terms when we feel it hurts legibility. So we shall write |Op (Get (Op (\x -> p
x `mplus` q x)))| to mean
|Op (Inl (Get (\x -> Op (Inr (p x `mplus` q x))))) :: Free (StateF + NondetF) a|. 
But due to this notation it might also mean
|Op (Inr (Get (\x -> Op (Inl (p x `mplus` q x))))) :: Free (NondetF + StateF)
a|, or a term of a more complicated type like
|Free (NondetF + (StateF + Nil)) a|. The type of the term will disambiguate our
meaning.
TODO mention the connection with algebraic effects.

%From this point onwards, we will omit some technical details where confusion is
%unlikely to arise. In particular, we will omit the |Op|, |Inl| and |Inr|
%constructors from our programs. For example, when we should write
%|Op (Inl (Get (\x -> Op (Inr (p x `mplus` q x)))))| (an instance of the type
%|Free (StateF + NondetF) a|), we shall instead write
%|Get (\x -> p x `mplus` q x)|, and by this actually mean an element of the type
%|Free (StateF + NondetF) a| instead of the type |StateF (NondetF a)|.
%Moreover, in our notation the same term is also an instance of
%|Free (NondetF + StateF) a|, and of |Free| 

\subsection{Folds and Fold Fusion}
Rather than defining our handlers directly by writing a general recursive
function, we will write them as folds, a type of structural recursion.
\begin{code}
  fold :: Functor f => (a -> r) -> (f r -> r) -> Free f r -> r
  fold gen alg (Ret x) = gen x
  fold gen alg (Op op) = alg (fmap (fold gen al) op)
\end{code}
This more principled approach gives us more leverage when reasoning about our
programs, as certain laws hold for programs defined through fusion.
In particular, we are interested in the {\em fold fusion} law:
\begin{align*}
  |h . fold gen alg| & = |fold gen' alg'| \\
                     & \Uparrow \\
  |h . gen|          & = |gen'| \\
  |h . alg|          & = |alg' . fmap h|
\end{align*}
Informally, this law states that a post-processing step (|h|) following a fold
can, if certain conditions are met, be {\em fused} into the fold.
Moreover, it will soon become apparent that the fold fusion law is not only
helpful in proving two known programs equivalent, but in fact it can often help
in finding a fused program given a composition of two programs. This discovered
program will then be correct by construction.

Our atomic handlers can be defined fairly straightforwardly through |fold|,
perhaps only the type of the handler requires some creativity (TODO give some
intuition how to come up with it?)

% Adapted from https://github.com/ivanperez-keera/lhs2tex-haskell-operators
%format <*> = "\mathbin{<\hspace{-1.6pt}\mathclap{\raisebox{0.1pt}{\scalebox{1}{$\ast$}}}\hspace{-1.6pt}>}"
%format <$> = "\mathbin{<\hspace{-1.6pt}\mathclap{\raisebox{0.1pt}{\scalebox{.8}{\$}}}\hspace{-1.6pt}>}"
%format ++  = "+\hspace{-4pt}+"

\begin{code}
hState :: Functor f => Free (StateF + f) a -> (S -> Free f (a,s))
hState = fold gen alg
  where  gen x                 = \ s -> Val (x,s)
         alg (Inl (Get k))     = \ s -> k s s
         alg (Inl (Put t k))   = \ _ -> k t
         alg (Inr p)           = \ s -> Op (fmap ($s) p)
  
hNondet :: Functor f => Free (NondetF + f) a -> Free f [a]
hNondet = fold gen alg
  where  gen x                     = Val [x]
         alg (Inl mzero)           = Val []
         alg (Inl (p `mplus` q))   = (++) <$> p <*> q
         alg (Inr op)              = Op op
\end{code}

Now that we have our atomic handlers defined, we have complete handlers for
local and global state as well, as we know how to compose them from the atomic
handlers. Nevertheless, these composed handlers have their drawbacks: firstly,
they run quite slowly because of the overhead of being passed through two
functions; and secondly, reasoning with them is a tad cumbersome because of the
size of the implementation.

We will use the fold fusion law to help us find fused implementations for local
and global state effects, which will be correct by construction.

Recall the composed handler for local state:
\begin{code}
hLocal :: Free (StateF + (NondetF + Nil)) a
hLocal = fmap (hNil . hNondet) . hState  
\end{code}
We apply the simplifications described earlier to rewrite as:
\begin{code}
hLocal :: Free (StateF + NondetF) a
hLocal = fmap hNondet . hState  
\end{code}
|hState| is a fold, which allows us to rewrite this implementation as
\begin{code}
hLocal = fmap hNondet . fold genState algState
  where
    genState x                 = \ s -> Val (x,s)
    algState (Inl (Get k  ) )  = \ s -> k s s
    algState (Inl (Put t k) )  = \ _ -> k t
    algState (Inr p         )  = \ s -> Op (fmap ($s) p)
\end{code} % $
Rewritten in this shape, the implementation of |hLocal| becomes amenable to fold
fusion:
\begin{align*}
  |fmap hNondet . fold genState algState| & = |fold genLocal algLocal| \\
                                          & \Uparrow \\
  |fmap hNondet . genState|               & = |genLocal| \\
  |fmap hNondet . algState|               & = |algLocal . fmap (fmap hNondet)|
\end{align*}
We follow this trail to discover definitions for |genLocal| and |algLocal|.

Finding the definition of |genLocal| is merely a matter of unfolding definitions.
\begin{code}
genLocal = fmap hNondet . genState
=== {- unfold |hNondet|, |genState| -}
genLocal = fmap (fold genNondet algNondet) . (\x s -> Val (x,s))  
=== {- unfold |(.)|, |fmap|, |fold| -}
genLocal = \x s -> genNondet (Val (x,s))  
=== {- unfold |genNondet| -}
genLocal = \x s -> Val [(x,s)]  
\end{code}

Finding |algLocal| is a bit more work. It is our intention to find a set of
equations for |algLocal| which, when taken together, form a complete definition. To
be more precise, if we can find the following four equations, where all free
variables are universally quantified, then we have found a definition for
|algLocal|.
\begin{code}
algLocal (Put t k)      = ?
algLocal (Get k)        = ?
algLocal mzero          = ?
algLocal (p `mplus` q)  = ?
\end{code}
We begin by applying both sides to an arbitrary argument, and then
proceed by case analysis on that argument.
\begin{code}
fmap hNondet . algState = algLocal . fmap (fmap hNondet)
=== {- apply both sides to |m|, unfold |(.)| -}
fmap hNondet (algState m) = algLocal (fmap (fmap hNondet) m)
\end{code}
First, we analyze the case |m = Put t k|. The general pattern of this case will
repeat in all other cases: first we unfold definitions, which yields an
application of |algLocal| to a term that is too specific, so we look for a way to
generalize the equation.
\begin{code}
fmap hNondet (algState (Put t k)) = algLocal (fmap (fmap hNondet) (Put t k))
=== {- unfold |algState|, |fmap| -}
fmap hNondet (\ _ -> k t) = algLocal (Put t (fmap hNondet k))
=== {- unfold |fmap| -}
hNondet . (\ _ -> k t) = algLocal (Put t (hNondet . k))
=== {- definition of |(.)| -}
\ _ -> (hNondet . k) t = algLocal (Put t (hNondet . k))
=== {- generalize |hNondet . k| as |k'| -}
\ _ -> k' t = algLocal (Put t k')
\end{code}
Initially the argument to |algLocal|, |Put t (hNondet . k)|, is too specific to cover all
cases, so we massage the other side of the equation until |hNondet . k| occurs
there too, so we can generalize both sides.

The case |m = Get k| proceeds quite similarly.
\begin{code}
fmap hNondet (algState (Get k)) = algLocal (fmap (fmap hNondet) (Get k))
=== {- unfolding definitions and reordering... -}
\ s -> (hNondet . k s) s = algLocal (\ s -> hNondet . k s)
=== {- $\lambda$-abstraction on LHS, $\alpha$-renaming on RHS -}
\ s -> ((\ t -> hNondet . k t) s) s = algLocal (Get (\ t -> hNondet . k t))
=== {- generalize |(\t -> hNondet . k t)| as |k'| -}
\ s -> k' s s = algLocal (Get k')
\end{code}

\begin{code}
fmap hNondet (algState (p `mplus` q)) = algLocal (fmap (fmap hNondet) (p `mplus` q))
=== {- unfolding definitions and reordering... -}
TODO
\end{code}

TODO complete proof.
TODO global state? surely in less detail

\subsection{|trans| as a Fold}
Recall the |trans| function from Section~\ref{sec:ctxt-trans}. Can we prove it
correct with respect to these specific implementations? The concrete proof
statement would be
\begin{code}
hGlobal . trans = hLocal
=== {- unfold |hLocal| -}
hGlobal . trans = fold genLocal algLocal
\end{code}
If only |trans| were a fold, then proving this equation would be easy! In that
case, we need only prove the two preconditions of the fold fusion law.
Fortunately, it is indeed the case that |trans| can be rewritten as a fold.
\begin{code}
trans :: Free (StateF + NondetF) a
trans = fold Val algTrans
  where
    algTrans (Put t k)  = Get (\s -> Put t k `mplus` Put s mzero)
    algTrans op         = Op op
\end{code}
It is then sufficient to prove the following two statements to prove
|hGlobal . trans = hLocal|.
\begin{align*}
  |hGlobal . Val|               & = |genLocal| \\
  |hGlobal . algTrans|          & = |algLocal . fmap hGlobal|
\end{align*}
TODO proof: there are no unknowns so the proof is merely ``verifying'', not sure
how interesting that will be.


% \begin{code}
%   
%   
%       putR s >> comp
%  ===  (get >>= \s0 -> put s `mplus` side (put s0)) >> comp
%  ===    {- monad law, left-distributivity \eqref{eq:bind-mplus-dist} -}
%       get >>= \s0 -> (put s >> comp) `mplus` (side (put s0) >> comp)
%  ===    {- by \eqref{eq:bind-mzero-zero} |mzero >> comp = mzero|, monad laws -}
%       get >>= \s0 -> (put s >> comp) `mplus` side (put s0) {-"~~."-}
% \end{code}