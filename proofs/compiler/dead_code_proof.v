(* ** License
 * -----------------------------------------------------------------------
 * Copyright 2016--2017 IMDEA Software Institute
 * Copyright 2016--2017 Inria
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 * ----------------------------------------------------------------------- *)

(* ** Imports and settings *)
From mathcomp Require Import all_ssreflect all_algebra.
Require Import psem compiler_util inline_proof.
Require Export dead_code.
Import Utf8.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Local Open Scope vmap.
Local Open Scope seq_scope.
  
Lemma write_memP gd (x:lval) v m1 m2 vm1 vm2:
  ~~ write_mem x -> 
  write_lval gd x v {| emem := m1; evm := vm1 |} = ok {| emem := m2; evm := vm2 |} ->
  m1 = m2.
Proof.
  case: x=> //= [v0 t|v0|v0 p] _.
  + by move=> /write_noneP [[]] ->.
  + by apply: rbindP=> z Hz [] ->.
  apply: on_arr_varP=> sz n t Ht Hval.
  apply: rbindP=> i; apply: rbindP=> x Hx Hi.
  apply: rbindP=> v1 Hv; apply: rbindP=> t0 Ht0.
  by apply: rbindP=> vm Hvm /= [] ->.
Qed.

Section PROOF.

  Variables p p' : prog.
  Context (gd: glob_defs).

  Hypothesis dead_code_ok : dead_code_prog p = ok p'.

  Let Pi_r (s:estate) (i:instr_r) (s':estate) :=
    forall ii s2,
      match dead_code_i (MkI ii i) s2 with
      | Ok (s1, c') =>
        wf_vm s.(evm) ->
        forall vm1', s.(evm) =[s1] vm1' ->
          exists vm2', s'.(evm) =[s2] vm2' /\ 
          sem p' gd (Estate s.(emem) vm1') c' (Estate s'.(emem) vm2')
      | _ => True
      end.

  Let Pi (s:estate) (i:instr) (s':estate) :=
    forall s2,
      match dead_code_i i s2 with
      | Ok (s1, c') =>
        wf_vm s.(evm) ->
        forall vm1', s.(evm) =[s1] vm1' ->
          exists vm2', s'.(evm) =[s2] vm2' /\ 
          sem p' gd (Estate s.(emem) vm1') c' (Estate s'.(emem) vm2')
      | _ => True
      end.

  Let Pc (s:estate) (c:cmd) (s':estate) :=
    forall s2, 
      match dead_code_c dead_code_i c s2 with
      | Ok (s1, c') =>
        wf_vm s.(evm) ->
        forall vm1', s.(evm) =[s1] vm1' ->
        exists vm2', s'.(evm) =[s2] vm2' /\ 
          sem p' gd (Estate s.(emem) vm1') c' (Estate s'.(emem) vm2')
      | _ => True
      end.

  Let Pfor (i:var_i) vs s c s' :=
    forall s2, 
      match dead_code_c dead_code_i c s2 with
      | Ok (s1, c') =>
        Sv.Subset (Sv.union (read_rv (Lvar i)) (Sv.diff s1 (vrv (Lvar i)))) s2 ->
        wf_vm s.(evm) ->
        forall vm1', s.(evm) =[s2] vm1' ->
        exists vm2', s'.(evm) =[s2] vm2' /\
          sem_for p' gd i vs (Estate s.(emem) vm1') c' (Estate s'.(emem) vm2')
      | _ => True
      end.

  Let Pfun m1 fn vargs m2 vres :=
    sem_call p' gd m1 fn vargs m2 vres.

  Local Lemma Hskip s : Pc s [::] s.
  Proof.
    case: s=> mem vm s2 Hwf vm' Hvm.
    exists vm'; split=> //.
    constructor.
  Qed.

  (* FIXME: MOVE THIS *)
  Lemma wf_sem_I p0 s1 i s2 :
    sem_I p0 gd s1 i s2 -> wf_vm (evm s1) -> wf_vm (evm s2).
  Proof.
    move=> H;have := sem_seq1 H; apply: wf_sem.
  Qed.

  Local Lemma Hcons s1 s2 s3 i c :
    sem_I p gd s1 i s2 ->
    Pi s1 i s2 -> sem p gd s2 c s3 -> Pc s2 c s3 -> Pc s1 (i :: c) s3.
  Proof.
    move=> H Hi H' Hc sv3 /=.
    have := Hc sv3.
    case: (dead_code_c dead_code_i c sv3)=> [[sv2 c']|//] Hc' /=.
    have := Hi sv2.
    case: (dead_code_i i sv2)=> [[sv1 i']|] //= Hi' Hwf vm1' /(Hi' Hwf).
    have Hwf2 := wf_sem_I H Hwf.
    move=> [vm2' [Heq2 Hsi']];case: (Hc' Hwf2 _ Heq2) => [vm3' [Heq3 Hsc']].
    exists vm3';split=> //.
    by apply: sem_app Hsi' Hsc'.
  Qed.

  Local Lemma HmkI ii i s1 s2 :
    sem_i p gd s1 i s2 -> Pi_r s1 i s2 -> Pi s1 (MkI ii i) s2.
  Proof. move=> _ Hi. exact: Hi. Qed.

  Lemma check_nop_spec (r:lval) ty (e:pexpr): check_nop r ty e ->
    exists x i1 i2, [/\ r = (Lvar (VarI x i1)), e = (Pvar(VarI x i2)) & ty = vtype x] .
  Proof. 
    case: r e => //= -[x1 i1] [] //= -[x2 i2] /= /andP [] /eqP <- /eqP ->.
    by exists x1, i1, i2. 
  Qed.

  Local Lemma Hassgn_aux ii m1 vm1 m2 vm2 v v' x tag ty e s2:
    sem_pexpr gd {| emem := m1; evm := vm1 |} e = ok v ->
    truncate_val ty v = ok v' ->
    write_lval gd x v' {| emem := m1; evm := vm1 |} = ok {| emem := m2; evm := vm2 |} ->
    wf_vm vm1 → 
    ∀ vm1' : vmap,
      vm1 =[read_rv_rec (read_e_rec (Sv.diff s2 (write_i (Cassgn x tag ty e))) e) x]  vm1' →
      ∃ vm2' : vmap, vm2 =[s2]  vm2'
        ∧ sem p' gd {| emem := m1; evm := vm1' |} [:: MkI ii (Cassgn x tag ty e)]
                    {| emem := m2; evm := vm2' |}.
  Proof.
    move=> Hv Hv' Hw Hwf vm1' Hvm.
    rewrite write_i_assgn in Hvm.
    move: Hvm; rewrite read_rvE read_eE=> Hvm.
    have [|vm2' [Hvm2 Hw2]] := write_lval_eq_on _ Hw Hvm; first by SvD.fsetdec.
    exists vm2'; split;first by apply: eq_onI Hvm2; SvD.fsetdec.
    apply: sem_seq1; constructor; econstructor; eauto.
    rewrite (@read_e_eq_on gd Sv.empty vm1 vm1') ?Hv // read_eE.
    by apply: eq_onS; apply: eq_onI Hvm; SvD.fsetdec.
  Qed.

  Local Lemma Hwrite_disj m1 m2 vm1 vm2 s2 x v:
    write_lval gd x v {| emem := m1; evm := vm1 |} = ok {| emem := m2; evm := vm2 |} ->
    disjoint s2 (vrv x) ->
    ~~ write_mem x ->
    vm1 =[s2]  vm2 /\ m1 = m2.
  Proof.
    move=> Hw Hdisj Hwmem;split.
    + by apply: disjoint_eq_on Hdisj Hw.
    by apply: write_memP Hwmem Hw.
  Qed.

  Local Lemma Hwrites_disj m1 m2 vm1 vm2 s2 x v:
    write_lvals gd {| emem := m1; evm := vm1 |} x v = ok {| emem := m2; evm := vm2 |} ->
    disjoint s2 (vrvs x) ->
    ~~ has write_mem x ->
    vm1 =[s2]  vm2 /\ m1 = m2.
  Proof.
    elim: x v m1 vm1 => [ | x xs Hrec] [ | v vs] //= m1 vm1.
    + by move=> [??];subst m1 vm1.
    apply: rbindP => -[m3 vm3] Hw Hws;rewrite /vrvs /= vrvs_recE -/vrv negb_or.
    move=> Hdisj /andP [] Hnw Hnh.
    have /(_ s2) [] := Hwrite_disj Hw _ Hnw.
    + by move: Hdisj;rewrite /disjoint /is_true !Sv.is_empty_spec;SvD.fsetdec.
    move=> Hvm ->;have [] := (Hrec _ _ _ Hws _ Hnh).
    + by move: Hdisj;rewrite /disjoint /is_true !Sv.is_empty_spec;SvD.fsetdec.
    by move=> ??;split => //;apply: (eq_onT Hvm).
  Qed.

  (* TODO: move *)
  Lemma truncate_val_Vundef ty1 ty2 v' : ~(truncate_val ty1 (Vundef ty2) = ok v').
  Proof.
    by rewrite /truncate_val;case: ty1 ty2 => //= [||??|?] [||??|?] //=; case:ifP.
  Qed.

  Local Lemma Hassgn s1 s2 x tag ty e v v':
    sem_pexpr gd s1 e = ok v -> 
    truncate_val ty v = ok v' ->
    write_lval gd x v' s1 = ok s2 ->
    Pi_r s1 (Cassgn x tag ty e) s2.
  Proof.
    move: s1 s2=> [m1 vm1] [m2 vm2] Hv htr Hw ii s2 /=.
    case: ifPn=> _ /=; last by apply: Hassgn_aux Hv htr Hw.
    case: ifPn=> /= [ | _].
    + rewrite write_i_assgn => /andP [Hdisj Hwmem] Hwf vm1' Hvm.
      have [? ->]:= Hwrite_disj Hw Hdisj Hwmem.
      exists vm1';split;last by constructor.
      by apply:eq_onT Hvm;apply eq_onS.
    case: ifPn=> Hnop /=;last by apply: Hassgn_aux Hv htr Hw.
    move=> Hwf vm1' Hvm.
    have Hs: {| emem := m1; evm := vm1 |} = {| emem := m2; evm := vm2 |}.
    + move: (check_nop_spec Hnop)=> {Hnop} [x0 [i1 [i2 [Hx He Hty]]]];subst x e.
      case: x0 Hty Hv Hw => ? xn0 /= <- Hv Hw.
      have ?: v' = v.
      + apply: on_vuP Hv=> [???|? [?]];subst;first by apply: truncate_pto_val htr.
        by elim: (truncate_val_Vundef htr).       
      subst.
      move: Hw;rewrite /= /write_var/set_var /=.
      apply: on_vuP Hv => /= [t|] Hx0 => [|[]] ?;subst v.
      + rewrite pof_val_pto_val /= => -[<-] <-;f_equal;apply: Fv.map_ext=> z.
        by case: ({|vtype := ty;vname := xn0|} =P z) => [<-|/eqP Hne];rewrite ?Fv.setP_eq ?Fv.setP_neq.
      t_xrbindP => vm3; apply: on_vuP;first by move=> ? /pof_val_undef_ok.
      case:ifP => // hty _ [] ???;subst.
      f_equal;apply: Fv.map_ext=> z.
      case: ({| vtype := ty; vname := xn0 |} =P z) => [<-|/eqP Hne];rewrite ?Fv.setP_eq ?Fv.setP_neq //.
      by have := Hwf {| vtype := ty; vname := xn0 |};rewrite Hx0;case : (ty) hty.
    exists vm1'; split.
    + apply: eq_onT Hvm.
      by case: Hs=> _ ->.
    by case: Hs=> -> _; exact: Eskip.
  Qed.

  Lemma check_nop_opn_spec (xs:lvals) (o:sopn) (es:pexprs): check_nop_opn xs o es ->
    exists x i1 sz i2, 
      [/\ xs = [:: Lvar (VarI (Var (sword sz) x) i1)], o = Ox86_MOV sz & es = [:: Pvar (VarI (Var (sword sz) x) i2)] ].
  Proof.
    case: xs o es => // rv [] // [] // sz [] // e [] //= /check_nop_spec [x [i1 [i2 []]]] -> -> /=.
    by case: x => ty xn /= <-;exists xn, i1, sz, i2.
  Qed.

  Lemma set_get_word vm1 vm2 sz xn v:
    let x := {| vtype := sword sz; vname := xn |} in
    get_var vm1 x = ok v ->
    set_var vm1 x v = ok vm2 ->
    vm1 = vm2.
  Proof.
    rewrite /get_var /set_var.
    apply: on_vuP=> [ /= t Hr <- /=| _ [<-] //].
    have -> /= := sumbool_of_boolET (pw_proof t).
    move=> [<-].
    apply: Fv.map_ext=> z.
    set x0 := {| vtype := _; vname := xn |}.
    case: (x0 =P z) => [<-|/eqP Hne];rewrite ?Fv.setP_eq ?Fv.setP_neq //.
    by rewrite -/x0 Hr;case: (t).
  Qed.

  Lemma get_var_word sz w x vm:
    get_var vm x = ok (@Vword sz w) ->
    exists sz', vtype x = sword sz' /\ (sz <= sz')%CMP.
  Proof.
    move: x=> [vt vn]; rewrite /=.
    rewrite /get_var /on_vu.
    case Hv: vm.[_]=> /= [v|[] //] [] H {Hv}. 
    case: vt v H => //= sz' v /Vword_inj [e ];subst => /= ?.
    by exists sz';split=> //;apply pw_proof.
  Qed.

  Local Lemma Hopn_aux s0 ii xs t o es v vs s1 s2 :
    sem_pexprs gd s1 es = ok vs ->
    exec_sopn o vs = ok v ->
    write_lvals gd s1 xs v = ok s2 ->
    wf_vm (evm s1) → ∀ vm1' : vmap,
    evm s1 =[read_es_rec (read_rvs_rec (Sv.diff s0 (vrvs xs)) xs) es]  vm1' → 
    ∃ vm2' : vmap, evm s2 =[s0]  vm2' ∧ 
       sem p' gd {| emem := emem s1; evm := vm1' |} [:: MkI ii (Copn xs t o es)]
                 {| emem := emem s2; evm := vm2' |}.
  Proof.
    move=> /= Hexpr Hopn Hw Hwf vm1' Hvm.
    move: Hvm; rewrite read_esE read_rvsE=> Hvm.
    have [|vm2 [Hvm2 Hvm2']] := write_lvals_eq_on _ Hw Hvm; first by SvD.fsetdec.
    exists vm2; split.
    + by apply: eq_onI Hvm2; SvD.fsetdec.
    econstructor;last by constructor.
    constructor; constructor.
    rewrite /sem_sopn (@read_es_eq_on gd es Sv.empty (emem s1) vm1' (evm s1)).
    + have ->: {| emem := emem s1; evm := evm s1 |} = s1 by case: (s1).
      by rewrite Hexpr /= Hopn /=; exact: Hvm2'.
    by rewrite read_esE; symmetry; apply: eq_onI Hvm;SvD.fsetdec.
  Qed.

  Local Lemma Hopn s1 s2 t o xs es :
    sem_sopn gd o s1 xs es = ok s2 ->
    Pi_r s1 (Copn xs t o es) s2.
  Proof.
    apply: rbindP=> v; apply: rbindP=> x0 Hexpr Hopn Hw.
    rewrite /Pi_r /= => ii s0.
    case: ifPn => _ /=; last by apply: Hopn_aux Hexpr Hopn Hw.
    case:ifPn => [ | _] /=.
    + move=> /andP [Hdisj Hnh] Hwf vm1' Heq;exists vm1'.
      case: s1 s2 Hw Hexpr Hwf Heq => m1 vm1 [m2 vm2] Hw _ Hwf /= Heq.
      have [? ->]:= Hwrites_disj Hw Hdisj Hnh;split;last by constructor.
      by apply: eq_onT Heq;apply eq_onS.
    case:ifPn => [ | _ /=]; last by apply: Hopn_aux Hexpr Hopn Hw.
    move=> /check_nop_opn_spec [x [i1 [sz [i2 [???]]]]]; subst xs o es=> /=.
    move=> Hwf vm1' Hvm.
    have Hs: s1 = s2;last by subst s2; exists vm1'; split=> //; exact: Eskip.
    move: x0 Hexpr Hopn=> [] // x0 [] //=;last by  move=> ???; apply: rbindP.
    rewrite /sem_pexprs /=.
    apply: rbindP=> z Hexpr []?; subst z.
    apply: rbindP => v0 /of_val_word [sz0] [v0'] [hle ? ?]; subst.
    rewrite /x86_MOV;t_xrbindP => ? h; have ha := assertP h => ?;subst.
    move:Hw;rewrite /= /write_var;t_xrbindP => s3 vm3. 
    have [sz' /= [[? hle']]]:= get_var_word Hexpr;subst sz'.
    have ? := cmp_le_antisym hle' hle;subst sz0;rewrite zero_extend_u => Hset ??;subst. 
    move: s1 Hwf Hvm Hexpr Hset => [mem1 vm1] /= Hwf Hvm Hexpr Hset; f_equal.
    by apply: (set_get_word Hexpr).
  Qed.
         
  Local Lemma Hif_true s1 s2 e c1 c2 :
    sem_pexpr gd s1 e = ok (Vbool true) ->
    sem p gd s1 c1 s2 -> Pc s1 c1 s2 -> Pi_r s1 (Cif e c1 c2) s2.
  Proof.
    move=> Hval Hp Hc ii sv0 /=.
    case Heq: (dead_code_c dead_code_i c1 sv0)=> [[sv1 sc1] /=|//].
    case: (dead_code_c dead_code_i c2 sv0)=> [[sv2 sc2] /=|//] Hwf vm1' Hvm.
    move: (Hc sv0).
    rewrite Heq.
    move=> /(_ Hwf vm1') [|vm2' [Hvm2' Hvm2'1]].
    move: Hvm; rewrite read_eE=> Hvm.
    apply: eq_onI Hvm; SvD.fsetdec.
    exists vm2'; split=> //.
    econstructor; constructor.
    constructor=> //.
    symmetry in Hvm.
    rewrite (read_e_eq_on _ _ Hvm).
    have ->: {| emem := emem s1; evm := evm s1 |} = s1 by case: (s1).
    by rewrite Hval.
  Qed.    

  Local Lemma Hif_false s1 s2 e c1 c2 :
    sem_pexpr gd s1 e = ok (Vbool false) ->
    sem p gd s1 c2 s2 -> Pc s1 c2 s2 -> Pi_r s1 (Cif e c1 c2) s2.
  Proof.
    move=> Hval Hp Hc ii sv0 /=.
    case: (dead_code_c dead_code_i c1 sv0)=> [[sv1 sc1] /=|//].
    case Heq: (dead_code_c dead_code_i c2 sv0)=> [[sv2 sc2] /=|//] Hwf vm1' Hvm.
    move: (Hc sv0).
    rewrite Heq.
    move=> /(_ Hwf vm1') [|vm2' [Hvm2' Hvm2'1]].
    move: Hvm; rewrite read_eE=> Hvm.
    apply: eq_onI Hvm; SvD.fsetdec.
    exists vm2'; split=> //.
    econstructor; constructor.
    apply: Eif_false=> //.
    symmetry in Hvm.
    rewrite (read_e_eq_on _ _ Hvm).
    have ->: {| emem := emem s1; evm := evm s1 |} = s1 by case: (s1).
    by rewrite Hval.
  Qed.

  Lemma wloopP f ii n s sic:
    wloop f ii n s = ok sic →
    ∃ si s', Sv.Subset s si ∧ f si = ok (s', sic) ∧ Sv.Subset s' si.
  Proof.
    clear.
    elim: n s => // n ih s /=.
    apply: rbindP => // [[s' sci]] h.
    case: (boolP (Sv.subset _ _)) => //=.
    + move=> /Sv.subset_spec Hsub k; apply ok_inj in k; subst.
      exists s, s'; split; auto. SvD.fsetdec.
    move=> _ hloop; case: (ih _ hloop) => si [si'] [Hsub] [h' le].
    exists si, si'; split; auto. SvD.fsetdec.
  Qed.

  Local Lemma Hwhile_true s1 s2 s3 s4 c e c' :
    sem p gd s1 c s2 -> Pc s1 c s2 ->
    sem_pexpr gd s2 e = ok (Vbool true) ->
    sem p gd s2 c' s3 -> Pc s2 c' s3 ->
    sem_i p gd s3 (Cwhile c e c') s4 -> Pi_r s3 (Cwhile c e c') s4 -> Pi_r s1 (Cwhile c e c') s4.
  Proof.
    move=> Hsc Hc H Hsc' Hc' Hsw Hw ii /= sv0.
    set dobody := (X in wloop X).
    case Hloop: wloop => [[sv1 [c1 c1']] /=|//].
    move: (wloopP Hloop) => [sv2 [sv2' [H1 [H2 H2']]]] Hwf vm1' Hvm.
    apply: rbindP H2 => -[sv3 c2'] Hc2'.
    set sv4 := read_e_rec _ _ in Hc2'.
    apply: rbindP => -[ sv5 c2 ] Hc2 x; apply ok_inj in x.
    repeat (case/xseq.pair_inj: x => ? x; subst).
    have := Hc sv4; rewrite Hc2' => /(_ Hwf vm1') [|vm2' [Hvm2'1 Hvm2'2]].
    + by apply: eq_onI Hvm.
    have Hwf2 := wf_sem Hsc Hwf.
    have := Hc' sv1;rewrite Hc2=> /(_ Hwf2 vm2') [|vm3' [Hvm3'1 Hvm3'2]].
    + apply: eq_onI Hvm2'1;rewrite /sv4 read_eE;SvD.fsetdec.
    have Hwf3 := wf_sem Hsc' Hwf2.
    have /= := Hw ii sv0;rewrite Hloop /= => /(_ Hwf3 _ Hvm3'1) [vm4' [Hvm4'1 Hvm4'2]].
    exists vm4';split => //.
    sinversion Hvm4'2;sinversion H6;sinversion H4.
    apply sem_seq1;constructor.
    apply: (Ewhile_true Hvm2'2) Hvm3'2 H6.
    have Hvm': vm2' =[read_e_rec sv0 e] evm s2.
    + by apply: eq_onI (eq_onS Hvm2'1);rewrite /sv4 !read_eE; SvD.fsetdec.
    by rewrite (read_e_eq_on _ (emem s2) Hvm');case: (s2) H.
  Qed.

  Local Lemma Hwhile_false s1 s2 c e c' :
    sem p gd s1 c s2 -> Pc s1 c s2 ->
    sem_pexpr gd s2 e = ok (Vbool false) ->
    Pi_r s1 (Cwhile c e c') s2.
  Proof.
    move=> Hsc Hc H ii sv0 /=.
    set dobody := (X in wloop X).
    case Hloop: wloop => [[sv1 [c1 c1']] /=|//] Hwf vm1' Hvm.
    move: (wloopP Hloop) => [sv2 [sv2' [H1 [H2 H2']]]].
    apply: rbindP H2 => -[sv3 c2'] Hc2.
    set sv4 := read_e_rec _ _ in Hc2.
    apply: rbindP => -[sv5 c2] Hc2' x; apply ok_inj in x.
    repeat (case/xseq.pair_inj: x => ? x; subst).
    have := Hc sv4;rewrite Hc2 => /(_ Hwf vm1') [|vm2' [Hvm2'1 Hvm2'2]].
    + by apply: eq_onI Hvm.
    exists vm2';split.
    + apply: eq_onI Hvm2'1;rewrite /sv4 read_eE;SvD.fsetdec.
    apply sem_seq1;constructor.
    apply: (Ewhile_false _ Hvm2'2).
    have Hvm': vm2' =[read_e_rec sv0 e] (evm s2).
    + by apply: eq_onS; apply: eq_onI Hvm2'1;rewrite /sv4 !read_eE; SvD.fsetdec.
    by rewrite (read_e_eq_on _ _ Hvm');case: (s2) H.
  Qed.

  Lemma loopP f ii n rx wx sv0 sv1 sc1:
    loop f ii n rx wx sv0 = ok (sv1, sc1) -> Sv.Subset sv0 sv1 /\
      exists sv2, f sv1 = ok (sv2, sc1) /\ Sv.Subset (Sv.union rx (Sv.diff sv2 wx)) sv1.
  Proof.
    elim: n sv0=> // n IH sv0 /=.
    apply: rbindP=> [[sv0' sc0']] Hone.
    case: (boolP (Sv.subset (Sv.union rx (Sv.diff sv0' wx)) sv0))=> /=.
    + move=> /Sv.subset_spec Hsub.
      rewrite /ciok=> -[??]; subst sv1 sc1;split=>//.
      by exists sv0'; split=>//; SvD.fsetdec.
    move=> _ Hloop.
    move: (IH _ Hloop)=> [Hsub [sv2 [Hsv2 Hsv2']]];split;first by SvD.fsetdec.
    by exists sv2.
  Qed.

  Local Lemma Hfor s1 s2 (i:var_i) d lo hi c vlo vhi :
    sem_pexpr gd s1 lo = ok (Vint vlo) ->
    sem_pexpr gd s1 hi = ok (Vint vhi) ->
    sem_for p gd i (wrange d vlo vhi) s1 c s2 ->
    Pfor i (wrange d vlo vhi) s1 c s2 -> Pi_r s1 (Cfor i (d, lo, hi) c) s2.
  Proof.
    move=> Hlo Hhi Hc Hfor ii /= sv0.
    case Hloop: (loop (dead_code_c dead_code_i c) ii Loop.nb Sv.empty (Sv.add i Sv.empty) sv0)=> [[sv1 sc1] /=|//].
    move: (loopP Hloop)=> [H1 [sv2 [H2 H2']]] Hwf vm1' Hvm.
    move: Hfor=> /(_ sv1); rewrite H2.
    move=> /(_ H2' Hwf vm1') [|vm2' [Hvm2'1 Hvm2'2]].
    move: Hvm; rewrite !read_eE=> Hvm.
    apply: eq_onI Hvm.
    SvD.fsetdec.
    exists vm2'; split.
    apply: eq_onI Hvm2'1.
    SvD.fsetdec.
    econstructor; constructor.
    econstructor.
    rewrite (read_e_eq_on _ _ (eq_onS Hvm)).
    have ->: {| emem := emem s1; evm := evm s1 |} = s1 by case: (s1).
    exact: Hlo.
    have Hhi': vm1' =[read_e_rec Sv.empty hi] (evm s1).
      move: Hvm; rewrite !read_eE=> Hvm.
      apply: eq_onI (eq_onS Hvm).
      SvD.fsetdec.
    rewrite (read_e_eq_on _ _ Hhi').
    have ->: {| emem := emem s1; evm := evm s1 |} = s1 by case: (s1).
    exact: Hhi.
    exact: Hvm2'2.
  Qed.

  Local Lemma Hfor_nil s i c: Pfor i [::] s c s.
  Proof.
   move=> sv0.
   case Heq: (dead_code_c dead_code_i c sv0) => [[sv1 sc1]|] //= Hsub Hwf vm1' Hvm.
   exists vm1'; split=> //.
   apply: EForDone.
  Qed.

  Local Lemma Hfor_cons s1 s1' s2 s3 (i : var_i) (w:Z) (ws:seq Z) c :
    write_var i w s1 = Ok error s1' ->
    sem p gd s1' c s2 ->
    Pc s1' c s2 ->
    sem_for p gd i ws s2 c s3 -> Pfor i ws s2 c s3 -> Pfor i (w :: ws) s1 c s3.
  Proof.
    move=> Hw Hsc Hc Hsfor Hfor sv0.
    case Heq: (dead_code_c dead_code_i c sv0) => [[sv1 sc1]|] //= Hsub Hwf vm1' Hvm.
    have [vm1'' [Hvm1''1 Hvm1''2]] := write_var_eq_on Hw Hvm.
    move: Hc=> /(_ sv0).
    rewrite Heq.
    have Hwf' := wf_write_var Hwf Hw.
    move=> /(_ Hwf' vm1'') [|vm2' [Hvm2'1 Hvm2'2]].
    apply: eq_onI Hvm1''1; SvD.fsetdec.
    move: Hfor=> /(_ sv0).
    rewrite Heq.
    move=> /(_ _ _ vm2') [|||vm3' [Hvm3'1 Hvm3'2]] //.
    apply: wf_sem Hsc Hwf'.
    exists vm3'; split=> //.
    econstructor.
    exact: Hvm1''2.
    exact: Hvm2'2.
    exact: Hvm3'2.
  Qed.

  Local Lemma Hcall s1 m2 s2 ii xs fn args vargs vs:
    sem_pexprs gd s1 args = Ok error vargs ->
    sem_call p gd (emem s1) fn vargs m2 vs ->
    Pfun (emem s1) fn vargs m2 vs ->
    write_lvals gd {| emem := m2; evm := evm s1 |} xs vs = Ok error s2 ->
    Pi_r s1 (Ccall ii xs fn args) s2.
  Proof.
    move=> Hexpr Hcall Hfun Hw ii' sv0.
    rewrite /= => Hwf vm1' Hvm.
    have [|vm2 [Hvm2 /= Hvm2']] := write_lvals_eq_on _ Hw Hvm.
      rewrite read_esE read_rvsE; SvD.fsetdec.
    exists vm2; split.
    apply: eq_onI Hvm2.
    rewrite read_esE read_rvsE.
    SvD.fsetdec.
    econstructor; constructor.
    econstructor.
    rewrite (read_es_eq_on _ (emem s1) (eq_onS Hvm)).
    have ->: {| emem := emem s1; evm := evm s1 |} = s1 by case: (s1).
    exact: Hexpr.
    exact: Hfun.
    exact: Hvm2'.
  Qed.

  Local Lemma Hproc m1 m2 fn f vargs vargs' s1 vm2 vres vres' :
    get_fundef p fn = Some f ->
    mapM2 ErrType truncate_val f.(f_tyin) vargs' = ok vargs ->
    write_vars (f_params f) vargs {| emem := m1; evm := vmap0 |} = ok s1 ->
    sem p gd s1 (f_body f) {| emem := m2; evm := vm2 |} ->
    Pc s1 (f_body f) {| emem := m2; evm := vm2 |} ->
    mapM (fun x : var_i => get_var vm2 x) (f_res f) = ok vres ->
    mapM2 ErrType truncate_val f.(f_tyout) vres = ok vres' ->
    Pfun m1 fn vargs' m2 vres'.
  Proof.
    move=> Hfun htra Hw Hsem Hc Hres Hfull.
    have [f' [Hf'1 Hf'2]] := get_map_cfprog dead_code_ok Hfun.
    case: f Hf'1 Hfun htra Hw Hsem Hc Hres Hfull=> ??? /= c ? res Hf'1 Hfun htra Hw Hsem Hc Hres Hfull.
    case: f' Hf'1 Hf'2=> ??? c' ? f'_res Hf'1 Hf'2.
    case Hd: (dead_code_c dead_code_i c (read_es [seq Pvar i | i <- res])) Hf'1 =>// [[sv sc]] /= Heq.
    rewrite /ciok in Heq.
    move: Heq=> [Heqi Heqp Heqc Heqr].
    move: Hc=> /(_ (read_es [seq Pvar i | i <- res])).
    have /= /(_ wf_vmap0) Hwf := wf_write_vars _ Hw.
    rewrite Hd => /(_ Hwf (evm s1)) [//|vm2' [Hvm2'1 /= Hvm2'2]] ??;subst.
    case: s1 Hvm2'2 Hw Hsem Hwf => /= ?? Hvm2'2 Hw Hsem Hwf.   
    econstructor. 
    + exact: Hf'2. + exact htra. + exact Hw. + exact Hvm2'2. 
    2: exact Hfull.
    rewrite -Hres; have /= <- := (@sem_pexprs_get_var gd (Estate m2 vm2) f'_res).
    have /= <- := (@sem_pexprs_get_var gd (Estate m2 vm2') f'_res);symmetry.
    by apply: read_es_eq_on Hvm2'1.
  Qed.

  Lemma dead_code_callP fn mem mem' va vr:
    sem_call p gd mem fn va mem' vr ->
    sem_call p' gd mem fn va mem' vr.
  Proof.
    apply (@sem_call_Ind p gd Pc Pi_r Pi Pfor Pfun Hskip Hcons HmkI Hassgn Hopn
            Hif_true Hif_false Hwhile_true Hwhile_false Hfor Hfor_nil Hfor_cons Hcall Hproc).
  Qed.

End PROOF.
