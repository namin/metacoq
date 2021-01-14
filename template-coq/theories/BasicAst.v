(* Distributed under the terms of the MIT license. *)
From Coq Require Import ssreflect Morphisms.
From MetaCoq.Template Require Import utils.
From Coq Require Floats.SpecFloat.

(** ** Reification of names ** *)

(** [Comment taken from Coq's code]
    - Id.t is the type of identifiers, that is morally a subset of strings which
      only contains Unicode characters of the Letter kind (and a few more).
      => [ident]
    - Name.t is an ad-hoc variant of Id.t option allowing to handle optionally
      named objects.
      => [name]
    - DirPath.t represents generic paths as sequences of identifiers.
      => [dirpath]
    - Label.t is an equivalent of Id.t made distinct for semantical purposes.
      => [ident]
    - ModPath.t are module paths.
      => [modpath]
    - KerName.t are absolute names of objects in Coq.
      => [kername]

    And also :
    - Constant.t => [kername]
    - variable => [ident]
    - MutInd.t => [kername]
    - inductive => [inductive]
    - constructor => [inductive * nat]
    - Projection.t => [projection]
    - GlobRef.t => global_reference

    Finally, we define the models of primitive types (uint63 and floats64).
*)

Definition ident   := string. (* e.g. nat *)
Definition qualid  := string. (* e.g. Datatypes.nat *)

(** Type of directory paths. Essentially a list of module identifiers. The
    order is reversed to improve sharing. E.g. A.B.C is ["C";"B";"A"] *)
Definition dirpath := list ident.

Instance dirpath_eqdec : Classes.EqDec dirpath := _.

Definition string_of_dirpath : dirpath -> string
  := String.concat "." ∘ rev.

(** The module part of the kernel name.
    - MPfile is for toplevel libraries, i.e. .vo files
    - MPbound are parameters of functors
    - MPdot is for submodules
*)
Inductive modpath :=
| MPfile  (dp : dirpath)
| MPbound (dp : dirpath) (id : ident) (i : nat)
| MPdot   (mp : modpath) (id : ident).
Derive NoConfusion EqDec for modpath.

Fixpoint string_of_modpath (mp : modpath) : string :=
  match mp with
  | MPfile dp => string_of_dirpath dp
  | MPbound dp id _ => string_of_dirpath dp ^ "." ^ id
  | MPdot mp id => string_of_modpath mp ^ "." ^ id
  end.

(** The absolute names of objects seen by kernel *)
Definition kername := modpath × ident.
Instance kername_eqdec : Classes.EqDec kername := _.

Definition string_of_kername (kn : kername) :=
  string_of_modpath kn.1 ^ "." ^ kn.2.

(** Identifiers that are allowed to be anonymous (i.e. "_" in concrete syntax). *)
Inductive name : Set :=
| nAnon
| nNamed (_ : ident).
Derive NoConfusion EqDec for name.

Inductive relevance : Set := Relevant | Irrelevant.
Derive NoConfusion EqDec for relevance.

(** Binders annotated with relevance *)
Record binder_annot (A : Type) := mkBindAnn { binder_name : A; binder_relevance : relevance }.

Arguments mkBindAnn {_}.
Arguments binder_name {_}.
Arguments binder_relevance {_}.

Derive NoConfusion for binder_annot.

Instance eqdec_binder_annot (A : Type) (e : Classes.EqDec A) : Classes.EqDec (binder_annot A).
Proof. ltac:(Equations.Prop.Tactics.eqdec_proof). Qed.

Definition map_binder_annot {A B} (f : A -> B) (b : binder_annot A) : binder_annot B :=
  {| binder_name := f b.(binder_name); binder_relevance := b.(binder_relevance) |}.

Definition eq_binder_annot {A B} (b : binder_annot A) (b' : binder_annot B) : Prop :=
  b.(binder_relevance) = b'.(binder_relevance).

(** Type of annotated names *)
Definition aname := binder_annot name.
Instance anqme_eqdec : Classes.EqDec aname := _.

Definition eqb_binder_annot {A} (b b' : binder_annot A) : bool :=
  match Classes.eq_dec b.(binder_relevance) b'.(binder_relevance) with
  | left _ => true
  | right _ => false
  end.

Definition string_of_name (na : name) :=
  match na with
  | nAnon => "_"
  | nNamed n => n
  end.

Definition string_of_relevance (r : relevance) :=
  match r with
  | Relevant => "Relevant"
  | Irrelevant => "Irrelevant"
  end.

(** Designation of a (particular) inductive type. *)
Record inductive : Set := mkInd { inductive_mind : kername ;
                                  inductive_ind : nat }.
Arguments mkInd _%string _%nat.

Derive NoConfusion EqDec for inductive.

Definition string_of_inductive (i : inductive) :=
  string_of_kername (inductive_mind i) ^ "," ^ string_of_nat (inductive_ind i).

Definition projection : Set := inductive * nat (* params *) * nat (* argument *).

(** Kernel declaration references [global_reference] *)
Inductive global_reference :=
| VarRef : ident -> global_reference
| ConstRef : kername -> global_reference
| IndRef : inductive -> global_reference
| ConstructRef : inductive -> nat -> global_reference.

Derive NoConfusion EqDec for global_reference.


Definition string_of_gref gr : string :=
  match gr with
  | VarRef v => v
  | ConstRef s => string_of_kername s
  | IndRef (mkInd s n) =>
    "Inductive " ^ string_of_kername s ^ " " ^ (string_of_nat n)
  | ConstructRef (mkInd s n) k =>
    "Constructor " ^ string_of_kername s ^ " " ^ (string_of_nat n) ^ " " ^ (string_of_nat k)
  end.

Definition kername_eq_dec (k k0 : kername) : {k = k0} + {k <> k0} := Classes.eq_dec k k0.
Hint Resolve kername_eq_dec : eq_dec.

Definition gref_eq_dec (gr gr' : global_reference) : {gr = gr'} + {~ gr = gr'} := Classes.eq_dec gr gr'.

Definition ident_eq (x y : ident) :=
  match string_compare x y with
  | Eq => true
  | _ => false
  end.

Lemma ident_eq_spec x y : reflect (x = y) (ident_eq x y).
Proof.
  unfold ident_eq. destruct (string_compare_eq x y).
  destruct string_compare; constructor; auto.
  intro Heq; specialize (H0 Heq). discriminate.
  intro Heq; specialize (H0 Heq). discriminate.
Qed.

(* todo : better ? *)
Definition eq_kername (k k0 : kername) : bool :=
  match kername_eq_dec k k0 with
  | left _ => true
  | right _ => false
  end.

Lemma eq_kername_refl kn : eq_kername kn kn.
Proof.
  unfold eq_kername. destruct (kername_eq_dec kn kn); cbnr.
  contradiction.
Qed.

Definition eq_inductive i i' :=
  let 'mkInd i n := i in
  let 'mkInd i' n' := i' in
  eq_kername i i' && Nat.eqb n n'.

Definition eq_constant := eq_kername.

Definition eq_projection p p' :=
  let '(ind, pars, arg) := p in
  let '(ind', pars', arg') := p' in
  eq_inductive ind ind' && Nat.eqb pars pars' && Nat.eqb arg arg'.

Lemma eq_inductive_refl i : eq_inductive i i.
Proof.
  destruct i as [mind k].
  unfold eq_inductive. now rewrite eq_kername_refl PeanoNat.Nat.eqb_refl.
Qed.

Lemma eq_projection_refl i : eq_projection i i.
Proof.
  destruct i as [[mind k] p].
  unfold eq_projection.
  now rewrite eq_inductive_refl !PeanoNat.Nat.eqb_refl.
Qed.

(** The kind of a cast *)
Inductive cast_kind : Set :=
| VmCast
| NativeCast
| Cast
| RevertCast.
Derive NoConfusion EqDec for cast_kind.

Record case_info := { ci_ind : inductive; ci_npar : nat; ci_relevance : relevance }.
Derive NoConfusion EqDec for case_info.

Definition string_of_case_info ci := 
  "(" ^ string_of_inductive ci.(ci_ind) ^ "," ^
  string_of_nat ci.(ci_npar) ^ "," ^
  string_of_relevance ci.(ci_relevance) ^ ")".

Inductive recursivity_kind :=
  | Finite (* = inductive *)
  | CoFinite (* = coinductive *)
  | BiFinite (* = non-recursive, like in "Record" definitions *).
Derive NoConfusion EqDec for recursivity_kind.

(* The kind of a conversion problem *)
Inductive conv_pb :=
  | Conv
  | Cumul.
Derive NoConfusion EqDec for conv_pb.

(* This opaque natural number is a hack to inform unquoting to generate
  a fresh evar when encountering it. *)
Definition fresh_evar_id : nat. exact 0. Qed.

(* Parametrized by term because term is not yet defined *)
Record def term := mkdef {
  dname : aname; (* the name, annotated with relevance **)
  dtype : term;
  dbody : term; (* the body (a lambda term). Note, this may mention other (mutually-defined) names **)
  rarg  : nat  (* the index of the recursive argument, 0 for cofixpoints **) }.

Arguments dname {term} _.
Arguments dtype {term} _.
Arguments dbody {term} _.
Arguments rarg {term} _.

Derive NoConfusion for def.
Instance def_eq_dec {A} : Classes.EqDec A -> Classes.EqDec (def A).
Proof. ltac:(Equations.Prop.Tactics.eqdec_proof). Qed.

Definition string_of_def {A} (f : A -> string) (def : def A) :=
  "(" ^ string_of_name (binder_name (dname def))
      ^ "," ^ string_of_relevance (binder_relevance (dname def))
      ^ "," ^ f (dtype def)
      ^ "," ^ f (dbody def)
      ^ "," ^ string_of_nat (rarg def) ^ ")".

Definition print_def {A} (f : A -> string) (g : A -> string) (def : def A) :=
  string_of_name (binder_name (dname def)) ^ " { struct " ^ string_of_nat (rarg def) ^ " }" ^
                 " : " ^ f (dtype def) ^ " := " ^ nl ^ g (dbody def).


Definition map_def {A B} (tyf bodyf : A -> B) (d : def A) :=
  {| dname := d.(dname); dtype := tyf d.(dtype); dbody := bodyf d.(dbody); rarg := d.(rarg) |}.

Lemma map_dtype {A B} (f : A -> B) (g : A -> B) (d : def A) :
  f (dtype d) = dtype (map_def f g d).
Proof. destruct d; reflexivity. Qed.

Lemma map_dbody {A B} (f : A -> B) (g : A -> B) (d : def A) :
  g (dbody d) = dbody (map_def f g d).
Proof. destruct d; reflexivity. Qed.

Definition mfixpoint term := list (def term).

Definition test_def {A} (tyf bodyf : A -> bool) (d : def A) :=
  tyf d.(dtype) && bodyf d.(dbody).

Definition tFixProp {A} (P P' : A -> Type) (m : mfixpoint A) :=
  All (fun x : def A => P x.(dtype) * P' x.(dbody))%type m.

Lemma map_def_map_def {A B C} (f f' : B -> C) (g g' : A -> B) (d : def A) :
  map_def f f' (map_def g g' d) = map_def (f ∘ g) (f' ∘ g') d.
Proof.
  destruct d; reflexivity.
Qed.

Lemma compose_map_def {A B C} (f f' : B -> C) (g g' : A -> B) :
  (map_def f f') ∘ (map_def g g') = map_def (f ∘ g) (f' ∘ g').
Proof. reflexivity. Qed.

Lemma map_def_id {t} x : map_def (@id t) (@id t) x = id x.
Proof. now destruct x. Qed.
Hint Rewrite @map_def_id @map_id : map.

Lemma map_def_spec {A B} (P P' : A -> Type) (f f' g g' : A -> B) (x : def A) :
  P' x.(dbody) -> P x.(dtype) -> (forall x, P x -> f x = g x) ->
  (forall x, P' x -> f' x = g' x) ->
  map_def f f' x = map_def g g' x.
Proof.
  intros. destruct x. unfold map_def. simpl.
  now rewrite !H // !H0.
Qed.

Hint Extern 10 (_ < _)%nat => lia : all.
Hint Extern 10 (_ <= _)%nat => lia : all.
Hint Extern 10 (@eq nat _ _) => lia : all.
Hint Extern 0 (_ = _) => progress f_equal : all.
Hint Unfold on_snd snd : all.

Lemma on_snd_eq_id_spec {A B} (f : B -> B) (x : A * B) :
  f (snd x) = snd x <->
  on_snd f x = x.
Proof.
  destruct x; simpl; unfold on_snd; simpl. split; congruence.
Qed.
Hint Resolve -> on_snd_eq_id_spec : all.
Hint Resolve -> on_snd_eq_spec : all.

Lemma map_def_eq_spec {A B} (f f' g g' : A -> B) (x : def A) :
  f (dtype x) = g (dtype x) ->
  f' (dbody x) = g' (dbody x) ->
  map_def f f' x = map_def g g' x.
Proof.
  intros. unfold map_def; f_equal; auto.
Qed.
Hint Resolve map_def_eq_spec : all.

Lemma map_def_id_spec {A} (f f' : A -> A) (x : def A) :
  f (dtype x) = (dtype x) ->
  f' (dbody x) = (dbody x) ->
  map_def f f' x = x.
Proof.
  intros. rewrite (map_def_eq_spec _ _ id id); auto. destruct x; auto.
Qed.
Hint Resolve map_def_id_spec : all.

Lemma tfix_map_spec {A B} {P P' : A -> Type} {l} {f f' g g' : A -> B} :
  tFixProp P P' l -> (forall x, P x -> f x = g x) ->
  (forall x, P' x -> f' x = g' x) ->
  map (map_def f f') l = map (map_def g g') l.
Proof.
  intros.
  eapply All_map_eq. red in X. eapply All_impl; eauto. simpl.
  intros. destruct X0;
  eapply map_def_spec; eauto.
Qed.

Section Contexts.
  Context {term : Type}.
  (** *** The context of De Bruijn indices *)

  Record context_decl := mkdecl {
    decl_name : aname ;
    decl_body : option term ;
    decl_type : term
  }.
  Derive NoConfusion for context_decl.
End Contexts.
    
Arguments context_decl : clear implicits.

Definition map_decl {term term'} (f : term -> term') (d : context_decl term) : context_decl term' :=
  {| decl_name := d.(decl_name);
     decl_body := option_map f d.(decl_body);
     decl_type := f d.(decl_type) |}.

Lemma compose_map_decl {term term' term''} (g : term -> term') (f : term' -> term'') x :
  map_decl f (map_decl g x) = map_decl (f ∘ g) x.
Proof.
  destruct x as [? [?|] ?]; reflexivity.
Qed.
   
Lemma map_decl_ext {term term'} (f g : term -> term') x : (forall x, f x = g x) -> map_decl f x = map_decl g x.
Proof.
  intros H; destruct x as [? [?|] ?]; rewrite /map_decl /=; f_equal; auto.
  now rewrite (H t).
Qed.

Instance map_decl_proper {term term'} : Proper (`=1` ==> Logic.eq ==> Logic.eq) (@map_decl term term').
Proof.
  intros f g Hfg x y ->. now apply map_decl_ext.
Qed.

Instance map_decl_pointwise {term term'} : Proper (`=1` ==> `=1`) (@map_decl term term').
Proof. intros f g Hfg x. rewrite /map_decl.
  destruct x => /=. f_equal.
  - now rewrite Hfg.
  - apply Hfg.
Qed.
(*

Instance pointwise_subrelation {A B} : subrelation (`=1`) (@Logic.eq A ==> @Logic.eq B)%signature.
Proof.
  intros f g Hfg x y ->. now rewrite Hfg.
Qed.

Instance pointwise_subrelation_inv {A B} : subrelation (@Logic.eq A ==> @Logic.eq B)%signature  (`=1`).
Proof.
  intros f g Hfg x. now specialize (Hfg x x eq_refl).
Qed.*)

Definition map_context {term term'} (f : term -> term') (c : list (context_decl term)) :=
  List.map (map_decl f) c.

Instance map_context_proper {term term'} : Proper (`=1` ==> Logic.eq ==> Logic.eq) (@map_context term term').
Proof.
  intros f g Hfg x y ->.
  now rewrite /map_context Hfg.
Qed.

Lemma map_context_length {term term'} (f : term -> term') l : #|map_context f l| = #|l|.
Proof. now unfold map_context; rewrite map_length. Qed.
Hint Rewrite @map_context_length : len.

Definition test_decl {term} (f : term -> bool) (d : context_decl term) : bool :=
  option_default f d.(decl_body) true && f d.(decl_type).

Instance test_decl_proper {term} : Proper (`=1` ==> Logic.eq ==> Logic.eq) (@test_decl term).
Proof. 
  intros f g Hfg [na [b|] ty] ? <- => /=; rewrite /test_decl /=;
  now rewrite Hfg.
Qed.

Section ContextMap.
  Context {term term' : Type} (f : nat -> term -> term').

  Fixpoint mapi_context (c : list (context_decl term)) : list (context_decl term') :=
    match c with
    | d :: Γ => map_decl (f #|Γ|) d :: mapi_context Γ
    | [] => []
  end.
End ContextMap.

Instance mapi_context_proper {term term'} : Proper (`=2` ==> Logic.eq ==> Logic.eq) (@mapi_context term term').
Proof.
  intros f g Hfg Γ ? <-.
  induction Γ as [|[na [b|] ty] Γ]; simpl; auto; f_equal; auto; now rewrite Hfg.
Qed.

Lemma mapi_context_length {term} (f : nat -> term -> term) l : #|mapi_context f l| = #|l|.
Proof.
  induction l; simpl; auto.  
Qed.
Hint Rewrite @mapi_context_length : len.

Section ContextTest.
  Context {term : Type} (f : term -> bool).
  
  Fixpoint test_context (c : list (context_decl term)) : bool :=
    match c with
    | d :: Γ => test_context Γ && test_decl f d
    | [] => true
    end.
End ContextTest.

Instance test_context_proper {term} : Proper (`=1` ==> Logic.eq ==> Logic.eq) (@test_context term).
Proof. 
  intros f g Hfg Γ ? <-.
  induction Γ as [|[na [b|] ty] Γ]; simpl; auto; f_equal; auto; now rewrite Hfg.
Qed.

Section ContextTestK.
  Context {term : Type} (f : nat -> term -> bool) (k : nat).
  
  Fixpoint test_context_k (c : list (context_decl term)) : bool :=
    match c with
    | d :: Γ => test_context_k Γ && test_decl (f (#|Γ| + k)) d
    | [] => true
    end.
End ContextTestK.

Instance test_context_k_proper {term} : Proper (`=1` ==> Logic.eq ==> Logic.eq ==> Logic.eq) (@test_context_k term).
Proof. 
  intros f g Hfg k ? <- Γ ? <-.
  induction Γ as [|[na [b|] ty] Γ]; simpl; auto; f_equal; auto; now rewrite Hfg.
Qed.

(** Primitive types models (axiom free) *)

(** Model of unsigned integers *)   
Definition uint_size := 63.
Definition uint_wB := (2 ^ (Z.of_nat uint_size))%Z.
Definition uint63_model := { z : Z | ((0 <=? z) && (z <? uint_wB))%Z }.

Definition string_of_uint63_model (i : uint63_model) := string_of_Z (proj1_sig i).

(** Model of floats *)
Definition prec := 53%Z.
Definition emax := 1024%Z.
(** We consider valid binary encordings of floats as our model *)
Definition float64_model := sig (SpecFloat.valid_binary prec emax).

Definition string_of_float64_model (i : float64_model) := 
  "<float>".