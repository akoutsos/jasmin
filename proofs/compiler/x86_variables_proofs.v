From mathcomp Require Import all_ssreflect all_algebra.
Require Import x86_variables.
Import Utf8.
Import compiler_util psem x86_sem.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

(* -------------------------------------------------------------------- *)
Lemma inj_rflag_of_var ii x y v :
     rflag_of_var ii x = ok v
  -> rflag_of_var ii y = ok v
  -> x = y.
Proof.
case: x y => -[]// x [] []// y /=.
case Ex: (rflag_of_string x) => [vx|] // -[?]; subst vx.
case Ey: (rflag_of_string y) => [vy|] // -[?]; subst vy.
by f_equal; apply: (inj_rflag_of_string Ex Ey).
Qed.

(* -------------------------------------------------------------------- *)
Definition to_rbool (v : value) :=
  match v with
  | Vbool   b    => ok (Def b)
  | Vundef sbool => ok Undef
  | _            => type_error
  end.

Lemma to_rbool_inj v b b' :
  to_rbool v = ok b →
  to_rbool v = ok b' →
  b = b'.
Proof. by case: v => // [ v | [] // ] [<-] [<-]. Qed.

(* -------------------------------------------------------------------- *)
Definition of_rbool (v : RflagMap.rflagv) :=
  if v is Def b then Vbool b else Vundef sbool.

(* -------------------------------------------------------------------- *)
Lemma to_rboolK rfv : to_rbool (of_rbool rfv) = ok rfv.
Proof. by case: rfv. Qed.

(* -------------------------------------------------------------------- *)
Definition eqflags (m: estate) (rf: rflagmap) : Prop :=
  ∀ f v, get_var (evm m) (var_of_flag f) = ok v → value_uincl v (of_rbool (rf f)).

Variant lom_eqv (m : estate) (lom : x86_mem) :=
  | MEqv of
         emem m = xmem lom
    & (∀ r v, get_var (evm m) (var_of_register r) = ok v → value_uincl v (Vword (xreg lom r)))
    & eqflags m (xrf lom).

(* -------------------------------------------------------------------- *)
Definition value_of_bool (b: exec bool) : exec value :=
  match b with
  | Ok b => ok (Vbool b)
  | Error ErrAddrUndef => ok (Vundef sbool)
  | Error e => Error e
  end.

(* -------------------------------------------------------------------- *)
Lemma xgetreg_ex ii x r v s xs :
  lom_eqv s xs →
  reg_of_var ii x = ok r →
  get_var s.(evm) x = ok v →
  value_uincl v (Vword (xs.(xreg) r)).
Proof.
move: (@var_of_register_of_var x).
move => h [_ eqv _]; case: x h => -[] //= [] // x.
rewrite /register_of_var /=.
case: reg_of_string => [vx|] // /(_ _ erefl) <- {x} [<-] ok_v.
exact: eqv.
Qed.

Corollary xgetreg ii x r v s xs w :
  lom_eqv s xs →
  reg_of_var ii x = ok r →
  get_var s.(evm) x = ok v →
  to_word U64 v = ok w →
  xreg xs r = w.
Proof.
  move => eqm hx hv hw; move: (xgetreg_ex eqm hx hv) => /value_uincl_word -/(_ _ _ hw) [].
  by rewrite zero_extend_u. 
Qed.

(* -------------------------------------------------------------------- *)
Lemma xgetflag_ex ii m rf x f v :
  eqflags m rf →
  rflag_of_var ii x = ok f →
  get_var (evm m) x = ok v →
  value_uincl v (of_rbool (rf f)).
Proof.
move: (@var_of_flag_of_var x).
move => h eqm; case: x h => -[] //= x.
rewrite /flag_of_var /=.
case: rflag_of_string => [vx|] // /(_ _ erefl) <- {x} [<-] ok_v.
by move/(_ _ _ ok_v): eqm.
Qed.

Corollary xgetflag ii m rf x f v b :
  eqflags m rf →
  rflag_of_var ii x = ok f →
  get_var (evm m) x = ok v →
  to_bool v = ok b →
  rf f = Def b.
Proof.
move => eqm ok_f ok_v ok_b.
have := xgetflag_ex eqm ok_f ok_v.
case: {ok_v} v ok_b => //.
- by move => b' [<-]; case: (rf _) => // ? ->.
by case.
Qed.

(* -------------------------------------------------------------------- *)
Lemma ok_sem_op1_b f v b :
  sem_op1_b f v = ok b ->
    exists2 vb, to_bool v = ok vb & b = Vbool (f vb).
Proof.
rewrite /sem_op1_b /mk_sem_sop1; t_xrbindP => /= vb ->.
by move=> ok_b; exists vb.
Qed.

(* -------------------------------------------------------------------- *)
Lemma ok_sem_op2_b f v1 v2 b :
  sem_op2_b f v1 v2 = ok b ->
    exists2 vb,
        [/\ to_bool v1 = ok vb.1 & to_bool v2 = ok vb.2]
      & b = Vbool (f vb.1 vb.2).
Proof.
rewrite /sem_op2_b /mk_sem_sop2; t_xrbindP.
by move=> vb1 ok1 vb2 ok2 fE; exists (vb1, vb2).
Qed.

(* -------------------------------------------------------------------- *)
Lemma eval_assemble_cond ii gd m rf e c v:
  eqflags m rf →
  assemble_cond ii e = ok c →
  sem_pexpr gd m e = ok v →
  ∃ v', value_of_bool (eval_cond c rf) = ok v' ∧ value_uincl v v'.
Proof.
move=> eqv; case: e => //.
+ move => x /=; t_xrbindP => r ok_r ok_ct ok_v.
  have := xgetflag_ex eqv ok_r ok_v.
  by case: {ok_r ok_v} r ok_ct => // -[<-] {c} /= h; eexists; split; eauto; case: (rf _).
+ do 2! case=> //; move=> x /=; t_xrbindP => r.
  move => ok_r ok_ct vx ok_vx /ok_sem_op1_b [vb ok_vb -> {v}].
  have := xgetflag eqv ok_r ok_vx ok_vb.
  by case: {ok_r ok_vx ok_vb} r ok_ct => // -[<-] {c} /= -> /=; eexists.
+ case=> //; first do 3! case=> //; move=> x.
  * case=> //; first do 2! case=> //; move=> y.
    - move=> /=; t_xrbindP => r1 ok_r1 r2 ok_r2.
      case: ifPn => // /andP[]; do 2! move/eqP=> ?; subst r1 r2.
      case=> <- resx vx ok_vx ok_resx resy vy ok_vy ok_resy ok_v.
      have /ok_sem_op1_b[rxb ok_rxb resxE] := ok_resx.
      have /ok_sem_op1_b[ryb ok_ryb resyE] := ok_resy.
      have := xgetflag eqv ok_r1 ok_vx ok_rxb => CFE.
      have := xgetflag eqv ok_r2 ok_vy ok_ryb => ZFE.
      rewrite /eval_cond; rewrite CFE ZFE /=; subst resx resy.
      by move: ok_v; rewrite /sem_op2_b /mk_sem_sop2 /= => -[<-]; eauto.
    - case: y => // y; case=> // z; do 2! case=> //; case=> // t.
      move=> /=; t_xrbindP => rx ok_rx ry ok_ry rz ok_rz rt ok_rt.
      case: ifP => //; rewrite -!andbA => /and4P[].
      do 4! move/eqP=> ?; subst rx ry rz rt => -[<-].
      move=> vNx vx ok_vx ok_vNx res vby vy ok_vy ok_vby.
      move=> vz ok_vz vNt vt ok_vt ok_vNt.
      case: eqP => // hty [<-] {res} ok_v.
      have [vbx ok_vbx ?] := ok_sem_op1_b ok_vNx; subst vNx.
      have [vbt ok_vbt ?] := ok_sem_op1_b ok_vNt; subst vNt.
      have := xgetflag eqv ok_rx ok_vx ok_vbx => ZFE.
      have := xgetflag eqv ok_ry ok_vy ok_vby => SFE.
      have := xgetflag eqv ok_rt ok_vt ok_vbt => OFE.
      rewrite /= ZFE SFE OFE /=; move: ok_v.
      rewrite /sem_op2_b /mk_sem_sop2 /=.
      t_xrbindP=> vres; case: (boolP vby) => hvby //=; last first.
      + by case=> <- <-; rewrite [false == _]eq_sym /= eqbF_neg; eexists.
      have := inj_rflag_of_var ok_rz ok_rt => eq_zt.
      have {eq_zt} ?: vt = vz; [have := ok_vz | subst vz].
      + by rewrite eq_zt ok_vt => -[].
      by rewrite ok_vbt => -[<-] <-; eauto.
  * case: x => // x; case => // [y /=|].
    - t_xrbindP=> rx ok_rx ry ok_ry; case: ifP => //.
      case/andP; do 2! move/eqP=> ?; subst rx ry.
      case=> <- vx ok_vx vy ok_vy ok_v.
      have [[bx by_] /=] := ok_sem_op2_b ok_v => -[ok_bx ok_by] vE.
      have ->/= := xgetflag eqv ok_rx ok_vx ok_bx.
      have ->/= := xgetflag eqv ok_ry ok_vy ok_by.
      by rewrite vE; eauto.
    - case=> // y; do 2! case=> //; case=> // z; case=> //= t.
      t_xrbindP=> rx ok_rx ry ok_ry rz ok_rz rt ok_rt.
      case: ifP=> //; rewrite -!andbA => /and4P[].
      do 4! move/eqP=> ?; subst rx ry rz rt => -[<-].
      move=> vx ok_vx res vby vy ok_vy ok_vby vNz vz ok_vz ok_vNz vt ok_vt.
      case: eqP => // hty [<-] {res} ok_v.
      have [[vbx vbres]] := ok_sem_op2_b ok_v.
      rewrite /fst /snd => -[ok_vbx ok_vbres] ?; subst v.
      have [vbz ok_vbz ?] := ok_sem_op1_b ok_vNz; subst vNz.
      have := xgetflag eqv ok_rx ok_vx ok_vbx => ZFE.
      have := xgetflag eqv ok_ry ok_vy ok_vby => SFE.
      have := xgetflag eqv ok_rz ok_vz ok_vbz => OFE.
      rewrite /= ZFE SFE OFE /=; move: ok_vbres.
      case: (boolP vby) => hvby /= => [[<-]|].
      + by rewrite eq_sym eqb_id; eexists.
      have := inj_rflag_of_var ok_rz ok_rt => eq_zt.
      have {eq_zt} ?: vt = vz; [have := ok_vz | subst vt].
      + by rewrite eq_zt ok_vt => -[].
      by rewrite ok_vbz => -[<-]; rewrite eq_sym eqbF_neg negbK; eexists.
+ case=> // x [] // => [|[] // [] //] y.
  * case=> // -[] // -[] // z /=; t_xrbindP.
    move=> rx ok_rx ry ok_ry rz ok_rz.
    case: ifPn => //; rewrite -!andbA => /and3P[].
    do 3! move/eqP=> ?; subst rx ry rz.
    have eq_xy: v_var y = v_var z.
    - by apply/(inj_rflag_of_var ok_ry ok_rz).
    case=> <- vbx vx ok_vx ok_vbx vy ok_vy rvz vz ok_vz ok_rvz.
    case: eqP => // hty [<-] {v}.
    have /ok_sem_op1_b[vbz ok_vbz ?] := ok_rvz; subst rvz.
    have := xgetflag eqv ok_rx ok_vx ok_vbx => SFE.
    have := xgetflag eqv ok_rz ok_vz ok_vbz => OFE.
    rewrite /= SFE OFE /=; have := inj_rflag_of_var ok_ry ok_rz.
    move=> eq_yz; have {eq_yz} ?: vy = vz; [have := ok_vy|subst vy].
    - by rewrite eq_yz ok_vz => -[].
    eexists; split; first by eauto.
    case: vz {ok_vy ok_rvz ok_vz hty} ok_vbz => //; last by case.
    move => b [->] {b}.
    by case: vbx {SFE} ok_vbx.
  * case=> // z /=; t_xrbindP => vx ok_x vy ok_y vz ok_z.
    case: ifPn => //; rewrite -!andbA => /and3P[].
    do 3! move/eqP=> ?; subst vx vy vz; case=> <-.
    move=> vbx vx ok_vx ok_vbx vNy vy ok_vy ok_vNy vz ok_vz.
    case: eqP => // hty [<-] {v}.
    have /ok_sem_op1_b[vby ok_vby ?] := ok_vNy; subst vNy.
    have := xgetflag eqv ok_x ok_vx ok_vbx => SFE.
    have := xgetflag eqv ok_y ok_vy ok_vby => OFE.
    move: (inj_rflag_of_var ok_z ok_y) ok_vz.
    case: z {ok_z} => /= z _ -> {z}.
    rewrite ok_vy => -[] ?; subst vz.
    rewrite /= SFE {SFE} /= OFE {OFE} /=; eexists; split; first by eauto.
    case: vy {ok_vy hty} ok_vNy ok_vby => //; last by case.
    move => b [<-] [->] {b}.
    case: vbx {ok_vbx} => //.
    by case: vby.
Qed.

(* -------------------------------------------------------------------- *)
Definition sem_ofs m o : exec pointer :=
  match o with
  | Ofs_const z => ok z
  | Ofs_var x => get_var (evm m) x >>= to_pointer
  | Ofs_mul sc x =>
    Let w := get_var (evm m) x >>= to_pointer in
    ok (sc * w)%R
  | Ofs_add sc x z =>
    Let w := get_var (evm m) x >>= to_pointer in
    ok (sc * w + z)%R
  | Ofs_error => type_error
  end.
Import word.
Lemma addr_ofsP gd m e v w :
  sem_pexpr gd m e = ok v →
  to_pointer v = ok w →
  let ofs := addr_ofs e in
  (if ofs is Ofs_error then false else true) →
  sem_ofs m ofs = ok w.
Proof.
elim: e v w => //=.
- (* Cast Const *)
  case => // -[] // z ih v w ; t_xrbindP => ? ? [<-] [<-] <- [<-].
  by rewrite zero_extend_u.
- (* Pvar *)
  by move => x z w ->.
- (* Papp2 *)
  case => // -[] //.
  (* Add *)
  + move => [] // p ihp q ihq v w ; t_xrbindP => vp hvp vq hvq hv hw.
    case: (addr_ofs p) ihp => //; case: (addr_ofs q) ihq => //.
    * move => /= z /(_ _ _ hvq) hz z' /(_ _ _ hvp) hz' _ /=.
      move: hv => /=; rewrite /sem_op2_w /mk_sem_sop2; t_xrbindP => 
        wp /hz' /(_ erefl) [<-] {wp} wq /hz /(_ erefl) [<-] {wq} ?; subst v.
      by case: hw => <-; rewrite zero_extend_u.
    * move => /= z /(_ _ _ hvq) hz z' /(_ _ _ hvp) hz' _ /=.
      move: hv => /=; rewrite /sem_op2_w /mk_sem_sop2; t_xrbindP => wp /hz' /(_ erefl) [<-] {wp} wq /hz /(_ erefl).
      t_xrbindP => vz -> /= -> /= ?; subst v.
      case: hw => <-;f_equal;wring.
    * move => /= x z /(_ _ _ hvq) hz z' /(_ _ _ hvp) hz' _.
      move: hv hw => /=; rewrite /sem_op2_w /mk_sem_sop2; t_xrbindP => wp /hz' /(_ erefl) [<-] {wp} wq /hz /(_ erefl).
      by t_xrbindP => ? ? -> /= -> <- /= <- [<-];f_equal; wring.
    * move => /= z /(_ _ _ hvq) hz z' /(_ _ _ hvp) hz' _ /=.
      move: hv hw => /=; rewrite /sem_op2_w /mk_sem_sop2; t_xrbindP => wp /hz' /(_ erefl).
      by t_xrbindP => vz' -> /= -> wq /hz /(_ erefl) [<-] {wq} <- [<-] /=;f_equal;wring.
    move => /= z /(_ _ _ hvq) hz x z' /(_ _ _ hvp) hz' _ /=.
    move: hv hw => /=; rewrite /sem_op2_w /mk_sem_sop2; t_xrbindP => wp /hz' /(_ erefl).
    by t_xrbindP => y vz' -> /= -> /= <- ? /hz /(_ erefl) [<-] <- [<-];rewrite zero_extend_u.
  (* Mul *)
  move => [] // p ihp q ihq v w ; t_xrbindP => vp hvp vq hvq hv hw.
  case: (addr_ofs p) ihp => //; case: (addr_ofs q) ihq => //.
  * move => /= z /(_ _ _ hvq) hz z' /(_ _ _ hvp) hz' _ /=.
    move: hv => /=; rewrite /sem_op2_w /mk_sem_sop2; t_xrbindP => wp /hz' /(_ erefl) [<-] {wp} wq /hz /(_ erefl) [<-] {wq} ?; subst v.
    by case: hw => <-; f_equal;wring.
  * move => /= z /(_ _ _ hvq) hz z' /(_ _ _ hvp) hz' _ /=.
    move: hv => /=; rewrite /sem_op2_w /mk_sem_sop2; t_xrbindP => wp /hz' /(_ erefl) [<-] {wp} wq /hz /(_ erefl).
    by t_xrbindP => vz -> /= -> /= ?; subst v; f_equal; case: hw => <-;rewrite zero_extend_u.
  move => /= z /(_ _ _ hvq) hz z' /(_ _ _ hvp) hz' _.
  move: hv hw => /=; rewrite /sem_op2_w /mk_sem_sop2; t_xrbindP => wp /hz' /(_ erefl).
  by t_xrbindP => ? -> /= -> ? /hz /(_ erefl) [<-] <- /= [<-];f_equal;wring.
Qed.

(* -------------------------------------------------------------------- *)
Lemma xscale_ok ii z sc :
  scale_of_z' ii z = ok sc -> 
  z = word_of_scale sc.
Proof. 
  rewrite /scale_of_z' -[X in _ -> X = _]wrepr_unsigned.
  by case: sc (wunsigned z); do! case=> //. 
Qed.

(* -------------------------------------------------------------------- *)

(*
Lemma eval_oprd_of_pexpr ii gd sz s m e c v:
  lom_eqv s m →
  oprd_of_pexpr ii sz e = ok c →
  sem_pexpr gd s e = ok v →
  exists2 w,
    read_oprd gd sz c m = ok w &
    value_uincl v (Vword w).
Proof.
move=> eqv; case: e => //.
+ by case=> //= z [<-] [<-] /=; eexists.
+ move=> x; rewrite /oprd_of_pexpr /=; t_xrbindP.
  move=> r ok_r -[<-] ok_v /=; eexists; first by reflexivity.
  exact: xgetreg_ex eqv ok_r ok_v.
+ move=> g h; apply ok_inj in h; subst c; rewrite /= /get_global.
  case: (get_global_word _ _) => // v' h; apply ok_inj in h.
  by subst; eauto.
move=> x e /=; t_xrbindP => r1 ok_r1 w ok_w [<-].
move=> z o ok_o ok_z z' o' ok_o' ok_z' res ok_res <- {v} /=.
exists res => //; rewrite -ok_res; f_equal; first by case: eqv.
move: ok_w; rewrite /addr_of_pexpr.
have := addr_ofsP ok_o' ok_z'.
case: addr_ofs => //=.
+ move => ofs /(_ erefl) [<-] [<-] //=.
  rewrite /decode_addr /= !rw64.
  by rewrite (xgetreg eqv ok_r1 ok_o ok_z) I64.add_commut.
+ move => x' /(_ erefl); t_xrbindP => v hv ok_v r ok_r [<-].
  rewrite /decode_addr /= !rw64.
  by rewrite (xgetreg eqv ok_r1 ok_o ok_z) (xgetreg eqv ok_r hv ok_v).
+ move => ofs x1 /(_ erefl); t_xrbindP => ? ? hx1 hx3 <- ? hx2 sc /xscale_ok -> [<-].
  rewrite /decode_addr /= !rw64.
  by rewrite (xgetreg eqv ok_r1 ok_o ok_z) (xgetreg eqv hx2 hx1 hx3).
move => sc x' ofs /(_ erefl); t_xrbindP => ? ? hx2 hx3 <- ? hx1 ? /xscale_ok -> [<-].
rewrite /decode_addr /=.
rewrite (xgetreg eqv ok_r1 ok_o ok_z) (xgetreg eqv hx1 hx2 hx3).
by rewrite I64.add_commut I64.add_assoc.
Qed.
*)
