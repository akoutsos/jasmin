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

(* * Prove properties about semantics of dmasm input language *)

(* ** Imports and settings *)
From mathcomp Require Import all_ssreflect all_algebra.
Require Import sem compiler_util constant_prop_proof.
Require Export stack_alloc stack_sem.

Require Import Psatz.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Local Open Scope vmap.
Local Open Scope seq_scope.
Local Open Scope Z_scope.

(* --------------------------------------------------------------------------- *)

Lemma size_of_pos t s : size_of t = ok s -> (1 <= s).
Proof.
  case: t=> //= [sz p [] <-| sz [] <-]; have hsz := wsize_size_pos sz; nia.
Qed.

  Import Memory.

Definition stk_ok (w: pointer) (z:Z) :=
  wunsigned w + z < wbase Uptr /\
  forall ofs s,
    (0 <= ofs /\ ofs + wsize_size s <= z)%Z ->
    is_align (w + wrepr _ ofs) s = is_align (wrepr _ ofs) s.

Definition valid_map (m:map) (stk_size:Z) :=
  forall x px, Mvar.get m.1 x = Some px -> 
     exists sx, size_of (vtype x) = ok sx /\
     [/\ 0 <= px, px + sx <= stk_size,
      aligned_for (vtype x) px &
         forall y py sy, x != y ->  
           Mvar.get m.1 y = Some py -> size_of (vtype y) = ok sy ->
           px + sx <= py \/ py + sy <= px].

Section PROOF.
  Variable P: prog.
  Context (gd: glob_defs).
  Variable SP: sprog.

  Variable m:map.
  Variable stk_size : Z.
  Variable pstk : pointer.

  Hypothesis pstk_add : stk_ok pstk stk_size.

  Hypothesis validm : valid_map m stk_size.

  Definition valid_stk_word (vm1:vmap) (m2:mem) (pstk: pointer) (p: Z) sz vn :=
    valid_pointer m2 (pstk + wrepr _ p) sz /\
    forall v,
      vm1.[{| vtype := sword sz; vname := vn |}] = ok v ->
      read_mem m2 (pstk + wrepr _ p) sz = ok v.

  Definition valid_stk_arr (vm1:vmap) (m2:mem) (pstk: pointer) (p: Z) sz s vn :=
    forall off, (0 <= off < Zpos s)%Z ->
      valid_pointer m2 (pstk + (wrepr _ (wsize_size sz * off + p))) sz /\
      let t := vm1.[{| vtype := sarr sz s; vname := vn |}] in
      forall a, t = ok a ->
        forall v, FArray.get a off = ok v ->
          read_mem m2 (pstk + (wrepr _ (wsize_size sz * off + p))) sz = ok v.

  Definition valid_stk (vm1:vmap) (m2:mem) pstk :=
    forall x,
      match Mvar.get m.1 x with
      | Some p =>
        match vtype x with
        | sword sz => valid_stk_word vm1 m2 pstk p sz (vname x)
        | sarr sz s => valid_stk_arr vm1 m2 pstk p sz s (vname x)
        | _ => True
        end
      | _ => True
      end.

  Definition eq_vm (vm1 vm2:vmap) := 
    (forall (x:var), 
       ~~ is_in_stk m x -> ~~ is_vstk m x -> 
       eval_uincl vm1.[x] vm2.[x]).

  Lemma eq_vm_write vm1 vm2 x v v':
    eq_vm vm1 vm2 ->
    eval_uincl v v' -> 
    eq_vm vm1.[x <- v] vm2.[x <- v'].
  Proof.
    move=> Heqvm Hu w ??.
    case : (x =P w) => [<- | /eqP ?];first by rewrite !Fv.setP_eq.
    by rewrite !Fv.setP_neq //; apply Heqvm.
  Qed.

  Definition disjoint_stk m :=
    forall w sz,
      valid_pointer m w sz ->
      ~((wunsigned pstk <? wunsigned w + wsize_size sz) && (wunsigned w <? wunsigned pstk + stk_size)).

  Definition valid (s1 s2: estate) :=
    [/\ disjoint_stk (emem s1), 
        (forall w sz, valid_pointer (emem s1) w sz -> read_mem (emem s1) w sz = read_mem (emem s2) w sz),
        (forall w sz, valid_pointer (emem s2) w sz = valid_pointer (emem s1) w sz || (between pstk stk_size w sz && is_align w sz)),
        eq_vm (evm s1) (evm s2) &
        get_var (evm s2) (vstk m) = ok (Vword pstk) /\
        valid_stk (evm s1) (emem s2) pstk ].

  (*
  Lemma get_valid_wrepr sz x p:
     Mvar.get m.1 {| vtype := sword sz; vname := x |} = Some p ->
     wunsigned pstk + p = wunsigned (wrepr Uptr (wunsigned pstk + p)).
  Proof.
  move=> Hget; have [sx /= [][]<-[]?? _]:= validm Hget.
  move: pstk_add (I64.unsigned_range pstk);rewrite /stk_ok/I64.max_unsigned.
  move=> ??;omega.
  Qed.

  Lemma get_valid_arepr sz x n p p1 :
    Mvar.get m.1 {| vtype := sarr sz n; vname := x |} = Some p ->
    0 <= p1 < Z.pos n ->
    wunsigned pstk + (wsize_size sz * p1 + p) = wunsigned (wrepr Uptr (wunsigned pstk + (wsize_size sz * p1 + p))).
  Proof.
    move=> Hget Hp1; have [sx [][]<-[]?? _]:= validm Hget.
    rewrite I64.unsigned_repr //.
    move: pstk_add (I64.unsigned_range pstk);rewrite /stk_ok/I64.max_unsigned.
    move=> ??. lia. 
  Qed.

  Lemma get_valid_repr x sz ofs :
    size_of (vtype x) = ok sz ->
    Mvar.get m.1 x = Some ofs ->
    wunsigned pstk + ofs = wunsigned (wrepr Uptr (wunsigned pstk + ofs)).
  Proof.
    move=> Hsz Hget.
    case: x Hget Hsz=> [[]] //.
    + move=> sz' n vn Hget _.
      have ->: ofs = wsize_size sz' * 0 + ofs by lia.
      by rewrite {1}(get_valid_arepr Hget).
    + move=> sz' vn Hget _.
      by rewrite {1}(get_valid_wrepr Hget).
  Qed.
   *)

  Lemma get_valid_word sz x p m1 m2:
     valid m1 m2 -> 
     Mvar.get m.1 {| vtype := sword sz; vname := x |} = Some p ->
     valid_pointer (emem m2) (pstk + wrepr _ p) sz.
  Proof.
    move=> [] H0 H1 _ H2 [H3 H4] Hget.
    by have := H4 {| vtype := sword sz; vname := x |};rewrite Hget /= => -[-> _].
  Qed.

  Lemma get_valid_arr sz x n p p1 m1 m2:
     valid m1 m2 ->
     Mvar.get m.1 {| vtype := sarr sz n; vname := x |} = Some p ->
     0 <= p1 < Zpos n ->
     valid_pointer (emem m2) (pstk + wrepr _ (wsize_size sz * p1 + p)) sz.
  Proof.
    move=> [] H0 H1 _ H2 [H3 H4] Hget Hp1.
    by have := H4 {| vtype := sarr sz n; vname := x |}; rewrite Hget => /(_ _ Hp1) [].
  Qed.

  (*
  (* TODO: move *)
  Lemma read_write_mem m1 v1 sz v2 m2 w k:
    write_mem m1 v1 sz v2 = ok m2 ->
    read_mem m2 w k = write_mem m1 v1 sz v2 >>= (fun m2 => read_mem m2 w k).
  Proof. by move=> ->. Qed.

  Lemma write_valid m1 m2 ptr sz v ptr' sz':
    write_mem m1 ptr sz v = ok m2 ->
    valid_pointer m1 ptr' sz' = valid_pointer m2 ptr' sz'.
  Proof.
    move=> H1.
    have Hr := read_write_mem _ _ H1.
    have Hv1 : valid_pointer m1 ptr sz by apply /(writeV m1 ptr v);exists m2.
    case Hw: (valid_pointer m1 ptr' sz');move /readV: (Hw).
    + move=> [w' Hw'];symmetry.
      apply/readV.
      case (v1 =P w) => [ | /eqP] Heq.
    + subst. apply /readV. rewrite Hr /=.
      + subst;apply /readV;exists v2. rewrite Hr Memory.writeP Hv1 eq_refl.
      by apply /readV;exists w'; rewrite Hr Memory.writeP (negbTE Heq) Hv1.
    move=> Hm1;symmetry;apply /readV => -[w'].
    rewrite Hr Memory.writeP Hv1;case:ifP => /eqP Heq.
    + by subst;move: Hv1;rewrite Hw.
    by move=> ?;apply Hm1;exists w'.
  Qed.

  Lemma read_mem_write_same sz addr sz' addr' val m1 m2 m1' m2':
    write_mem m1 addr sz val = ok m1' ->
    write_mem m2 addr sz val = ok m2' ->
    (forall w sz', valid_pointer m1 w sz' -> read_mem m1 w sz' = read_mem m2 w sz') ->
    valid_pointer m1 addr' sz' ->
    read_mem m1' addr' sz' = read_mem m2' addr' sz'.
  Proof.
    move=> Hw1 Hw2 Hother Hv'.
    have Hv1: valid_pointer m1 addr sz.
      apply/writeV; exists m1'; exact: Hw1.
    have Hv2: valid_pointer m2 addr sz.
      apply/writeV; exists m2'; exact: Hw2.
    rewrite (read_write_mem _ Hw1) (read_write_mem _ Hw2) !writeP Hv1 Hv2 Hother //.
  Qed.
*)

  (*
  Lemma add_repr_r x y : I64.add x (I64.repr y) = I64.repr (x + y).
  Proof.
    by apply: reqP; rewrite !urepr !I64.Z_mod_modulus_eq Zplus_mod_idemp_r eq_refl.
  Qed.
*)

  Lemma check_varP vm1 vm2 x1 x2 v:
    check_var m x1 x2 -> eq_vm vm1 vm2 -> 
    get_var vm1 x1 = ok v ->
    exists v', get_var vm2 x2 = ok v' /\ value_uincl v v'.
  Proof.
    move=> /andP [/andP [Hin_stk /eqP Heq12] Hnot_vstk] Heq Hget.
    have := Heq _ Hin_stk Hnot_vstk.
    move: Hget;rewrite /get_var Heq12; apply: on_vuP => [t | ] -> /=.
    + move=> <-;case vm2.[x2] => //= s Hs;exists (to_val s);split => //.
      by apply to_val_uincl.
    move=> [<-] /=;case vm2.[x2] => //= [s _ | ? <-].
    + by exists (to_val s);split => //;rewrite type_of_to_val.
    by exists (Vundef (vtype x2)).
  Qed.

  Lemma check_varsP vm1 vm2 x1 x2 vs:
    all2 (check_var m) x1 x2 -> eq_vm vm1 vm2 ->
    mapM (fun x : var_i => get_var vm1 x) x1 = ok vs ->
    exists vs', 
      mapM (fun x : var_i => get_var vm2 x) x2 = ok vs' /\
      List.Forall2 value_uincl vs vs'.
  Proof.
    elim: x1 x2 vs=> [|a l IH] [|a' l'] //= vs.
    + move=> _ Heq [<-];by exists [::].
    move=> /andP [Ha Hl] Heq.
    apply: rbindP => va /(check_varP Ha Heq) [v' [-> Hu]].
    apply: rbindP => tl  /(IH _ _ Hl Heq) [tl' [-> Hus]] [<-] /=.
    by exists (v' :: tl');split=>//;constructor.
  Qed.

  Lemma check_var_stkP s1 s2 sz x1 x2 e v:
    check_var_stk m sz x1 x2 e ->
    valid s1 s2 ->
    sem_pexpr gd s1 (Pvar x1) = ok v ->
    exists v', 
       sem_pexpr gd s2 (Pload sz x2 e) = ok v' /\ value_uincl v v'.
  Proof.
  case/andP => /andP [] /eqP Hvstk /eqP Htype.
  case Hget: (Mvar.get _ _) => [ ofs |] // /eqP -> {e}.
  case => _ _ _ _; rewrite - Hvstk.
  case => Hpstk /(_ x1); rewrite Hget Htype => -[] /= H H' Hvar.
  rewrite Hpstk /=.
  case: x1 Htype Hget Hvar H'=> [[x1t x1n] vi1] /= Htype Hget Hvar H'; subst.
  rewrite /zero_extend !wrepr_unsigned.
  move: Hvar.
  apply: on_vuP => /= [w | ].
  + by move => /H' -> <-; exists (Vword w).
    by move=> _ [<-];move /readV: H => [w -> /=];exists (Vword w).
  Qed.

  Lemma is_addr_ofsP sz ofs e1 e2 :
    is_addr_ofs sz ofs e1 e2 ->
    exists i, 
    e1 = Pconst i /\ 
    e2 = Pcast Uptr (wsize_size sz * i + ofs).
  Proof.
    rewrite /is_addr_ofs;case:is_constP => // i.
    by case: is_wconst_of_sizeP => // z /eqP <-; eauto.
  Qed.

  Opaque Z.mul.

  Lemma check_arr_stkP s1 s2 sz x1 e1 x2 e2 v:
    check_arr_stk m sz x1 e1 x2 e2 ->
    valid s1 s2 ->
    sem_pexpr gd s1 (Pget x1 e1) = ok v ->
    sem_pexpr gd s2 (Pload sz x2 e2) = ok v.
  Proof.
    case: x1 => [[xt1 xn1] ii1]; case/andP => /eqP Hvstk /=.
    case: xt1 => // sz1 n /andP [] /eqP -> {sz1}.
    case Hget: (Mvar.get m.1 _)=> [ofs|//] /is_addr_ofsP [i [??]];subst e1 e2.
    set x1 := {| vname := xn1 |}.
    move=> [H1 H2 H3 H4 [H5 H6]].
    apply: on_arr_varP=> sz' n' t /= [_ ?] Harr; subst n'.
    apply: rbindP => z Hgeti [<-].
    rewrite Hvstk H5 /=.
    have Hbound := Array.getP_inv Hgeti.
    have /andP [/ZleP H0le /ZltP Hlt]:= Hbound.
    rewrite /zero_extend !wrepr_unsigned.
    have := H6 x1; rewrite Hget /=.
    move=> /(_ i) [//| /=] ?.
    move: Harr;rewrite /get_var.
    apply: on_vuP => //= n0 Ht0 /Varr_inj [_] [?]; subst => /= ?; subst n0.
    move=> /(_ _ Ht0) H.
    by move: Hgeti; rewrite /Array.get Hbound => /H ->.
  Qed.

  Lemma check_eP (e1 e2: pexpr) (s1 s2: estate) v :
    check_e m e1 e2 -> valid s1 s2 -> sem_pexpr gd s1 e1 = ok v ->
    exists v', sem_pexpr gd s2 e2 = ok v' /\ value_uincl v v'.
  Proof.
    move=> He Hv; move: He.
    have Hvm: eq_vm (evm s1) (evm s2).
      by move: Hv=> -[].
    elim: e1 e2 v=> 
     [z1|b1|sz1 e1 IH|v1| g1 |v1 e1 IH|sz1 v1 e1 IH|o1 e1 IH|o1 e1 H1 e1' H1' | e He e1 H1 e1' H1'] e2 v.
    + by case: e2=> //= z2 /eqP -> [] <-;exists z2;auto.
    + by case: e2=> //= b2 /eqP -> [] <-;exists b2;auto.
    + case:e2 => //= sz2 e2 /andP [] /eqP <- {sz2} /IH {IH}IH.
      apply: rbindP => z;apply: rbindP => v1 /IH [v1' [->]] /= Hu.
      move=> /(value_uincl_int Hu) [??] [?];subst v1 v1' v => /=.
      by exists (Vword (wrepr sz1 z)); split => //; exists erefl.
    + case: e2 => //= [v2 | sz2 v2 e2].
      + by move=> /check_varP -/(_ _ _ _ Hvm) H/H. 
      move=> /check_var_stkP -/(_ _ _ _ Hv) H /H {H} [v' [Hload /= Hu]].
      by exists v';split.
    + by case: e2=>//= g2 /eqP -> ->; eauto.
    + case: e2=> //= [ | sz ] v2 e2.
      + move=> /andP [/check_varP Hv12 /IH{IH} He].
        apply: on_arr_varP=> sz n t Ht Harr /=.
        rewrite /on_arr_var. 
        have [v' [-> Hu] /=]:= Hv12 _ _ _ Hvm Harr.
        apply: rbindP=> i; apply: rbindP=> ve /He [ve' [-> Hve]].
        move=> /(value_uincl_int Hve) [??];subst ve ve'=> /=.
        apply: rbindP => w Hw [<-].
        case: v' Hu => //= sz' n' a [<-] [?]; subst => /= /(_ _ _ Hw) -> /=.
        by exists (Vword w); split => //; exists erefl.
      move=> He Hv1;exists v;split=>//.
      by apply: (check_arr_stkP He Hv Hv1).
    + case: e2=> // sz v2 e2 /= /andP [/andP [] /eqP -> Hv12 He12].
      apply: rbindP=> w1; apply: rbindP=> x1 Hx1 Hw1.
      apply: rbindP=> w2; apply: rbindP=> x2 Hx2 Hw2.
      apply: rbindP=> w Hw -[] <-.
      exists (Vword w);split => //.
      have [x1' [->]]:= check_varP Hv12 Hvm Hx1.
      move=> /value_uincl_word -/(_ _ _ Hw1) /=; rewrite /to_pointer => -> /=.
      have [v' [-> /= Hu]]:= IH _ _ He12 Hx2.
      rewrite (value_uincl_word Hu Hw2) /=.
      suff : read_mem (emem s2) (w1 + w2) sz = ok w by move => ->.
      rewrite -Hw;case: Hv => _ -> //.
      by apply/readV; exists w; exact: Hw.
    + case: e2=> // o2 e2 /= /andP []/eqP <- /IH He.
      apply: rbindP=> b /He [v' []] -> /vuincl_sem_sop1 Hu /Hu /= ->.
      by exists v.
    + case: e2=> // o2 e2 e2' /= /andP [/andP [/eqP -> /H1 He] /H1' He'].
      apply: rbindP=> v1 /He [v1' []] -> /vuincl_sem_sop2 Hu1.
      apply: rbindP=> v2 /He' [v2' []] -> /Hu1 Hu2 /Hu2 /= ->. 
      by exists v.
    case: e2 => // e' e2 e2' /= /andP[] /andP[] /He{He}He /H1{H1}H1 /H1'{H1'}H1'.
    apply: rbindP => b;apply: rbindP => w /He [b' [->]] /value_uincl_bool.
    move=> H /H [??];subst w b'=> /=.
    t_xrbindP=> v1 /H1 [] v1' [] -> Hv1' v2 /H1' [] v2' [] -> Hv2'.
    t_xrbindP=> y2 Hy2 y3 Hy3 <- /=.
    rewrite -(type_of_val_uincl Hv1').
    have [? [-> _]] /= := of_val_uincl Hv1' Hy2.
    have [? [-> _]] /= := of_val_uincl Hv2' Hy3.
    eexists; split=> //.
    by case: (b).
  Qed.

  Lemma check_esP (es es': pexprs) (s1 s2: estate) vs :
    all2 (check_e m) es es' -> valid s1 s2 ->
    sem_pexprs gd s1 es = ok vs ->
    exists vs',  
      sem_pexprs gd s2 es' = ok vs' /\
      List.Forall2 value_uincl vs vs'.
  Proof.
    rewrite /sem_pexprs;elim: es es' vs=> //= [|a l IH] [ | a' l'] //= vs.
    + by move=> _ Hv [<-];eauto.
    move=> /andP [Ha Hl] Hvalid.
    apply: rbindP => v /(check_eP Ha Hvalid) [v' [->] Hu].
    apply: rbindP => vs1 /(IH _ _ Hl Hvalid) [vs' [->] Hus] [<-] /=.
    by exists (v' :: vs');split=>//;constructor.
  Qed.

  Lemma valid_stk_write_notinstk s1 s2 vi v:
    ~~ (is_in_stk m vi) ->
    valid_stk (evm s1) (emem s2) pstk ->
    valid_stk (evm s1).[vi <- v] (emem s2) pstk.
  Proof.
    move=> Hnotinstk Hstk x.
    move: Hstk=> /(_ x).
    case Hget: (Mvar.get m.1 x)=> [get|] //.
    have Hx: x != vi.
      apply/negP=> /eqP Habs.
      by rewrite /is_in_stk -Habs Hget in Hnotinstk.
    case Htype: (vtype x)=> // [sz p|].
    + move=> H off Hoff.
      move: H=> /(_ off Hoff) [H H'].
      split=> //.
      move=> t a0 Ht v0 Haget.
      rewrite /= in H'.
      have Hvma: (evm s1).[{| vtype := sarr sz p; vname := vname x |}] = ok a0.
        rewrite -Ht /t Fv.setP_neq //.
        case: x Hget Hx Htype t a0 Ht Haget H'=> [xt xn] /= ?? Htype ?????.
        by rewrite -Htype eq_sym.
      by rewrite (H' _ Hvma _ Haget).
    + move=> [H H'];split=> //= v0; rewrite Fv.setP_neq;last first.
      + by rewrite eq_sym;case: (x) Htype Hx => ?? /= ->.
      by move=> /H'.
  Qed.

  Lemma valid_set_uincl s1 s2 vi v v': 
    vi != vstk m -> ~~ is_in_stk m vi ->
    valid s1 s2 -> eval_uincl v v' ->
    valid {| emem := emem s1; evm := (evm s1).[vi <- v] |}
          {| emem := emem s2; evm := (evm s2).[vi <- v'] |}.
  Proof.
    move=> neq nin [H1 H2 H3 H4 [H5 H6]] Hu;split=> //=.
    + by apply: eq_vm_write.
    split;first by rewrite /get_var Fv.setP_neq ?Hx //.
    by apply: valid_stk_write_notinstk.
  Qed.

  Lemma check_varW (vi vi': var_i) (s1 s2: estate) v v':
    check_var m vi vi' -> valid s1 s2 -> value_uincl v v' ->
    forall s1', write_var vi v s1 = ok s1' ->
    exists s2', write_var vi' v' s2 = ok s2' /\ valid s1' s2'.
  Proof.
    move=> /andP [/andP [Hnotinstk /eqP Heq] Hnotstk] Hval Hu s1'. 
    rewrite /write_var -Heq => {Heq vi'}.
    (apply: rbindP=> z /=; apply: set_varP;rewrite /set_var) => 
       [ t | /negbTE ->]. 
    + move=> /(of_val_uincl Hu) [t' [-> Htt']] <- [<-].
      exists {| emem := emem s2; evm := (evm s2).[vi <- ok t'] |};split=>//.
      by apply valid_set_uincl.
    move=> /of_val_error ?;subst v.
    move: Hu;rewrite /= => /eqP Hu <- [<-].
    have := of_val_type_of v';rewrite -Hu => -[[v'']|] -> /=.
    + exists {| emem := emem s2; evm := (evm s2).[vi <- ok v''] |};split => //.
      by apply valid_set_uincl => //; apply eval_uincl_undef.
    exists {| emem := emem s2; evm := (evm s2).[vi <- undef_addr (vtype vi)] |};split=>//.
    by apply valid_set_uincl.
  Qed.

  Lemma check_varsW (vi vi': seq var_i) (s1 s2: estate) v v':
    all2 (check_var m) vi vi' -> valid s1 s2 -> 
    List.Forall2 value_uincl v v' -> 
    forall s1', write_vars vi v s1 = ok s1' ->
    exists s2', write_vars vi' v' s2 = ok s2' /\ valid s1' s2'.
  Proof.
    elim: vi vi' v v' s1 s2 => [|a l IH] [|a' l'] //= [|va vl] [|va' vl'] s1 s2 //=.
    + by move=> _ Hv _ s1' []<-; exists s2.
    + by move=> _ _ H;sinversion H.
    + by move=> _ _ H;sinversion H.
    move=> /andP [Ha Hl] Hv H s1';sinversion H.
    apply: rbindP=> x Hwa.
    move: (check_varW Ha Hv H3 Hwa)=> [s2' [Hs2' Hv2']] Hwl.
    move: (IH _ _ _ _ _ Hl Hv2' H5 _ Hwl)=> [s3' [Hs3' Hv3']].
    by exists s3'; split=> //; rewrite Hs2' /= Hs3'.
  Qed.

  Lemma vtype_diff x x': vtype x != vtype x' -> x != x'.
  Proof. by apply: contra => /eqP ->. Qed.

  Lemma vname_diff x x': vname x != vname x' -> x != x'.
  Proof. by apply: contra => /eqP ->. Qed.

  Lemma var_stk_diff x x' get get' sz:
    Mvar.get m.1 x = Some get ->
    Mvar.get m.1 x' = Some get' ->
    x != x' ->
    size_of (vtype x') = ok sz ->
    get != get'.
  Proof.
    move=> Hget Hget' Hneq Hsz.
    apply/negP=> /eqP Habs.
    rewrite -{}Habs in Hget'.
    move: (validm Hget)=> [sx] [Hsx1] [_ _ _] /(_ _ _ _ Hneq Hget' Hsz) [].
    have := (size_of_pos Hsx1); lia.
    have := (size_of_pos Hsz); lia.
  Qed.

  Lemma var_stk_diff_off x x' get get' off sz:
    Mvar.get m.1 x = Some get ->
    Mvar.get m.1 x' = Some get' ->
    x != x' ->
    size_of (vtype x') = ok sz ->
    0 <= off < sz ->
    get != off + get'.
  Proof.
    move=> Hget Hget' Hneq Hsz Hoff.
    apply/negP=> /eqP Habs.
    rewrite {}Habs in Hget.
    move: (validm Hget)=> [sx [Hsx1 [Hsx2 Hsx3 _ /(_ _ _ _ Hneq Hget' Hsz) [|]]]].
    have := (size_of_pos Hsx1); lia.
    have := (size_of_pos Hsz); lia.
  Qed.

  Lemma var_stk_diff_off_l x x' get get' off sz:
    Mvar.get m.1 x = Some get ->
    Mvar.get m.1 x' = Some get' ->
    x != x' ->
    size_of (vtype x) = ok sz ->
    0 <= off < sz ->
    get + off != get'.
  Proof.
    move=> Hget Hget' Hneq Hsz Hoff.
    apply/negP=> /eqP Habs.
    rewrite -{}Habs in Hget'.
    rewrite eq_sym in Hneq.
    move: (validm Hget')=> [sx [Hsx1 [Hsx2 Hsx3 _ /(_ _ _ _ Hneq Hget Hsz) [|]]]].
    have := (size_of_pos Hsx1); lia.
    have := (size_of_pos Hsz); lia.
  Qed.

  Lemma var_stk_diff_off_both x x' get get' off off' sz sz':
    Mvar.get m.1 x = Some get ->
    Mvar.get m.1 x' = Some get' ->
    x != x' ->
    size_of (vtype x) = ok sz ->
    size_of (vtype x') = ok sz' ->
    0 <= off < sz ->
    0 <= off' < sz' ->
    get + off != get' + off'.
  Proof.
    move=> Hget Hget' Hneq Hsz Hsz' Hoff Hoff'.
    apply/negP=> /eqP Habs.
    rewrite eq_sym in Hneq.
    (* TODO: check if optimal *)
    move: (validm Hget')=> [sx [Hsx1 [Hsx2 Hsx3 _ /(_ _ _ _ Hneq Hget Hsz) [|]]]].
    have := (size_of_pos Hsx1).
    rewrite eq_sym in Hneq.
    move: (validm Hget)=> [sx' [Hsx'1 [Hsx'2 Hsx'3 _ /(_ _ _ _ Hneq Hget' Hsz') [|]]]].
    have := (size_of_pos Hsx'1); lia.
    lia.
    have := (size_of_pos Hsz); lia.
  Qed.

  Lemma wunsigned_pstk_add ofs :
    0 <= ofs -> ofs <= stk_size ->
    wunsigned (pstk + wrepr Uptr ofs) = wunsigned pstk + ofs.
  Proof.
  move => p1 p2.
  apply: wunsigned_add.
  case: (pstk_add) => h _.
  have := wunsigned_range pstk.
  lia.
  Qed.

  Lemma le_of_add_le x y sz :
    x + wsize_size sz <= y ->
    x <= y.
  Proof. have := wsize_size_pos sz; lia. Qed.

  Lemma valid_get_w sz vn ofs :
    Mvar.get m.1 {| vtype := sword sz; vname := vn |} = Some ofs ->
    between pstk stk_size (pstk + wrepr Uptr ofs) sz && is_align (pstk + wrepr Uptr ofs) sz.
  Proof.
    case: pstk_add => hstk halign Hget.
    move: (validm Hget)=> [sx [/= [] Hsz [Hsx Hsx' Hal Hoverlap]]].
    subst.
    apply/andP; split.
    + have h := wunsigned_pstk_add Hsx (le_of_add_le Hsx').
      apply/andP; rewrite h; split; apply/ZleP; lia.
    rewrite halign => //; lia.
  Qed.

  (*
  Lemma valid_get_a vn get n:
    Mvar.get m.1 {| vtype := sarr n; vname := vn |} = Some get ->
    (pstk <=? I64.add pstk (I64.repr get)) && (I64.add pstk (I64.repr get) <? pstk + stk_size).
  Proof.
    move=> Hget.
    move: (validm Hget)=> [sx [/= [] Hsz [Hsx Hsx' _]]].
    have ->: get = 8 * 0 + get by [].
    apply/andP; split.
    apply: Zle_imp_le_bool.
    rewrite add_repr_r.
    rewrite -(get_valid_arepr Hget); lia.
    rewrite add_repr_r.
    apply Zlt_is_lt_bool.
    rewrite -(get_valid_arepr Hget); lia.
  Qed.

  Lemma valid_get_a_off vn get n off:
    Mvar.get m.1 {| vtype := sarr n; vname := vn |} = Some get ->
    0 <= off < Z.pos n ->
    (pstk <=? I64.add pstk (I64.repr (8 * off + get))) && (I64.add pstk (I64.repr (8 * off + get)) <? pstk + stk_size).
  Proof.
    move=> Hget Hoff.
    move: (validm Hget)=> [sx [/= [] Hsz [Hsx Hsx' _]]].
    apply/andP; split.
    apply: Zle_imp_le_bool.
    rewrite add_repr_r.
    rewrite -(get_valid_arepr Hget); lia.
    rewrite add_repr_r.
    apply Zlt_is_lt_bool.
    rewrite -(get_valid_arepr Hget); lia.
  Qed.
*)

  Lemma valid_stk_arr_var_stk s1 s2 sz xwn sz' xan ofsw ofsa n w m':
    let xw := {| vname := xwn; vtype := sword sz |} in
    Mvar.get m.1 xw = Some ofsw ->
    let xa := {| vname := xan; vtype := sarr sz' n |} in
    Mvar.get m.1 xa = Some ofsa ->
    write_mem (emem s2) (pstk + wrepr _ ofsw) sz w = ok m' ->
    valid_pointer (emem s2) (pstk + wrepr _ ofsw) sz ->
    valid_stk_arr (evm s1) (emem s2) pstk ofsa sz' n xan ->
    valid_stk_arr (evm s1).[xw <- ok w] m' pstk ofsa sz' n xan.
  Proof.
    move=> xw Hgetw xa Hgeta Hm' Hvmem H off Hoff.
    move: H=> /(_ off Hoff) [Hoff1 Hoff2]; split.
    - by rewrite (write_valid _ _ Hm').
    have hxwa : xw != xa by rewrite vtype_diff.
    rewrite Fv.setP_neq=> [t a Ht v0 Hv0| //].
    rewrite -(Hoff2 _ Ht _ Hv0).
    apply: (writeP_neq Hm').
    case: (validm Hgetw) => sx [] [<-] {sx} [hw hw' hxal] /(_ _ _ _ hxwa Hgeta erefl) hdisj.
    case: (validm Hgeta) => sa [] [<-] {sa} [ha ha' haal] _.
    split.
    - by apply: is_align_no_overflow; apply: valid_align Hvmem.
    - by apply: is_align_no_overflow; apply: valid_align Hoff1.
    have : wunsigned (pstk + wrepr _ ofsw) = wunsigned pstk + ofsw.
    - by apply: (wunsigned_pstk_add hw (le_of_add_le hw')).
    have hsz' := wsize_size_pos sz'.
    have : wunsigned (pstk + wrepr _ (wsize_size sz' * off + ofsa)) = wunsigned pstk + wsize_size sz' * off + ofsa.
    - by rewrite wunsigned_pstk_add; nia.
    have hsz := wsize_size_pos sz.
    case: hdisj => h; [ left | right ]; nia.
  Qed.

  Lemma valid_stk_word_var_stk s1 s2 sz xn sz' xn' ofsx ofsx' m' w:
    let x := {| vtype := sword sz; vname := xn |} in
    Mvar.get m.1 x = Some ofsx ->
    let x' := {| vtype := sword sz'; vname := xn' |} in
    Mvar.get m.1 x' = Some ofsx' ->
    write_mem (emem s2) (pstk + wrepr _ ofsx) sz w = ok m' ->
    valid_pointer (emem s2) (pstk + wrepr _ ofsx) sz ->
    valid_stk_word (evm s1) (emem s2) pstk ofsx' sz' xn' ->
    valid_stk_word (evm s1).[x <- ok w] m' pstk ofsx' sz' xn'.
  Proof.
    move=> vi Hget x Hget' Hm' Hvmem [H H']; split=> //.
    - by rewrite (write_valid _ _ Hm').
    rewrite /= -/x => v.
    case: (vi =P x).
    + subst vi x; case => ? ?; subst.
      rewrite Fv.setP_eq => -[<-]; clarify.
      exact: (writeP_eq Hm').
    move/eqP => hvix.
    rewrite Fv.setP_neq // => Hread.
    rewrite (writeP_neq Hm'). exact: H'.
    split.
    - by apply: is_align_no_overflow; apply: valid_align Hvmem.
    - by apply: is_align_no_overflow; apply: valid_align H.
    case: (validm Hget) => sx [] [<-] {sx} [hw hw' hxal] /(_ _ _ _ hvix Hget' erefl) hdisj.
    case: (validm Hget') => sa [] [<-] {sa} [ha ha' haal] _.
    have : wunsigned (pstk + wrepr _ ofsx) = wunsigned pstk + ofsx.
    - by apply: (wunsigned_pstk_add hw (le_of_add_le hw')).
    have haha : wunsigned (pstk + wrepr _ ofsx') = wunsigned pstk + ofsx'.
    - by apply: (wunsigned_pstk_add ha (le_of_add_le ha')).
    lia.
  Qed.

  Lemma valid_stk_var_stk s1 s2 sz (w: word sz) m' xn ofs ii:
    let vi := {| v_var := {| vtype := sword sz; vname := xn |}; v_info := ii |} in
    Mvar.get m.1 vi = Some ofs ->
    write_mem (emem s2) (pstk + wrepr _ ofs) sz w = ok m' ->
    valid_pointer (emem s2) (pstk + wrepr _ ofs) sz ->
    valid_stk (evm s1) (emem s2) pstk ->
    valid_stk (evm s1).[{| vtype := sword sz; vname := xn |} <- ok w] m' pstk.
  Proof.
    move=> vi Hget Hm' Hvmem H x; move: H=> /(_ x).
    case Hget': (Mvar.get m.1 x)=> [ofs'|//].
    move: x Hget'=> [[| |sz' n| sz'] vn] //= Hget' H.
    + exact: (valid_stk_arr_var_stk Hget Hget' Hm').
    + exact: (valid_stk_word_var_stk Hget Hget' Hm').
  Qed.

  Lemma valid_var_stk s1 xn sz w s2 m' ofs ii:
    valid s1 s2 ->
    write_mem (emem s2) (pstk + wrepr _ ofs) sz w = ok m' ->
    let vi := {| v_var := {| vtype := sword sz; vname := xn |}; v_info := ii |} in
    Mvar.get m.1 vi = Some ofs ->
    valid {|
      emem := emem s1;
      evm := (evm s1).[{| vtype := sword sz; vname := xn |} <- ok w] |}
      {| emem := m'; evm := evm s2 |}.
  Proof.
    move=> [] H1 H2 H3 H4 [H5 H6] Hm' vi Hget.
    have Hmem : valid_pointer (emem s2) (pstk + wrepr _ ofs) sz.
    + by apply/writeV; eauto.
    split=> //=.
    + move=> w' sz' Hvalid.
      have [sx [hsx [ho1 ho2 hal hdisj]]] := validm Hget.
      have [hov hal'] := pstk_add.
      rewrite (H2 _ _ Hvalid); symmetry; apply: (writeP_neq Hm').
      split.
      - by apply: is_align_no_overflow; apply: valid_align Hmem.
      - by apply: is_align_no_overflow; apply: valid_align Hvalid.
      case: hsx => ?; subst sx.
      have : wunsigned (pstk + wrepr _ ofs) = wunsigned pstk + ofs.
      - by apply: (wunsigned_pstk_add ho1 (le_of_add_le ho2)).
      have := H1 _ _ Hvalid.
      case/negP/nandP => /ZltP /Z.nlt_ge h; lia.
    + by move=> w' sz'; rewrite -H3 -(write_valid _ _ Hm').
    + move=> x Hx1 Hx2.
      rewrite Fv.setP_neq; first exact: H4.
      apply/negP=> /eqP ?; subst x.
      by rewrite /is_in_stk Hget in Hx1.
    + split=> //.
      exact: (valid_stk_var_stk Hget Hm').
  Qed.

  Lemma check_var_stkW sz (vi vi': var_i) (s1 s2: estate) v v' e:
     check_var_stk m sz vi vi' e -> valid s1 s2 ->
     value_uincl v v' -> 
     forall s1', write_var vi v s1 = ok s1' ->
    exists s2' : estate, write_lval gd (Lmem sz vi' e) v' s2 = ok s2' /\ valid s1' s2'.
  Proof.
  case: vi => -[] xt xn ii /andP [] /andP [] /eqP Hisvstk /= /eqP -> {xt}.
  case Hget: (Mvar.get _ _) => [ ofs | ] // /eqP -> {e} Hv.
  case: (Hv) => H1 H2 H3 H4 [H5 H6] Hu s1'.
  rewrite Hisvstk H5 /=.
  apply: rbindP=> /= vm'; apply: set_varP => //= w.
  move=> /(value_uincl_word Hu) -> <- [<-] /=.
  rewrite /zero_extend !wrepr_unsigned.
  have Hvmem: valid_pointer (emem s2) (pstk + wrepr _ ofs) sz.
  + rewrite H3; apply/orP; right; exact: (valid_get_w Hget).
  have [m' Hm'] : exists m', write_mem (emem s2) (pstk + wrepr _ ofs) sz w = ok m'.
  + by apply/writeV.
  exists {| emem := m'; evm := evm s2 |}; split.
  + by rewrite Hm' /=.
  exact: valid_var_stk Hv Hm' Hget.
  Qed.

  Lemma pos_dec_n_n n: CEDecStype.pos_dec n n = left (erefl n).
  Proof. by elim: n=> // p0 /= ->. Qed.

  Lemma valid_stk_arr_arr_stk s1 s2 n n' sz xn sz' xn' ofsx ofsx' m' v0 i (a: Array.array n (word sz)) t:
    let x := {| vtype := sarr sz n; vname := xn |} in
    Mvar.get m.1 x = Some ofsx ->
    let x' := {| vtype := sarr sz' n'; vname := xn' |} in
    Mvar.get m.1 x' = Some ofsx' ->
    get_var (evm s1) x = ok (Varr a) ->
    valid_pointer (emem s2) (pstk + wrepr _ (wsize_size sz * i + ofsx)) sz ->
    write_mem (emem s2) (pstk + wrepr _ (wsize_size sz * i + ofsx)) sz v0 = ok m' ->
    Array.set a i v0 = ok t ->
    valid_stk_arr (evm s1) (emem s2) pstk ofsx' sz' n' xn' ->
    valid_stk_arr (evm s1).[x <- ok t] m' pstk ofsx' sz' n' xn'.
  Proof.
    move=> x Hget x' Hget' Ha Hvmem Hm' Ht.
    move=> H off Hoff.
    move: H=> /(_ off Hoff) [H /= H'].
    split=> //.
    - by rewrite (write_valid _ _ Hm').
    case: (x =P x').
    + subst x x'. case => ???; subst sz' n' xn' => a0.
      rewrite Fv.setP_eq => -[<-] {a0} v1 Hv1.
      rewrite Hget in Hget'; move: Hget'=> []?; subst ofsx'.
      move: (Ht).
      rewrite /Array.set; case: ifP => // /andP [] /ZleP Hi /ZltP Hi' [?]; subst t.
      move: Hv1; rewrite FArray.setP; case: eqP.
      * by move => <- [<-]; rewrite (writeP_eq Hm').
      move => hio Hv1.
      rewrite (writeP_neq Hm').
      * apply: (H' _ _ _ Hv1).
        by move: Ha; rewrite /get_var; apply: on_vuP => //= ? -> /Varr_inj1 ->.
      split.
      - by apply: is_align_no_overflow; apply: valid_align Hvmem.
      - by apply: is_align_no_overflow; apply: valid_align H.
      admit. (* arithmetic… needs axiom about alignement *)
    move => Hxx' a'.
    rewrite Fv.setP_neq; last by apply/eqP.
    move => /H'{H'}H' v /H'{H'}.
    rewrite (writeP_neq Hm') //.
    split.
    - by apply: is_align_no_overflow; apply: valid_align Hvmem.
    - by apply: is_align_no_overflow; apply: valid_align H.
    admit. (* validm implies disjointness *)
  Admitted.

  Lemma valid_stk_word_arr_stk n xan sz xwn sz' ofsa ofsw (a: Array.array n (word sz)) m' s1 s2 t v0 i:
    let xa := {| vtype := sarr sz n; vname := xan |} in
    Mvar.get m.1 xa = Some ofsa ->
    let xw := {| vtype := sword sz'; vname := xwn |} in
    Mvar.get m.1 xw = Some ofsw ->
    get_var (evm s1) xa = ok (Varr a) ->
    valid_pointer (emem s2) (pstk + wrepr _ (wsize_size sz * i + ofsa)) sz ->
    write_mem (emem s2) (pstk + wrepr _ (wsize_size sz * i + ofsa)) sz v0 = ok m' ->
    Array.set a i v0 = ok t ->
    valid_stk_word (evm s1) (emem s2) pstk ofsw sz' xwn ->
    valid_stk_word (evm s1).[xa <- ok t] m' pstk ofsw sz' xwn.
  Proof.
    move=> xa Hgeta xw Hgetw Ha Hvmem Hm' Ht [H H'].
    split.
    + by rewrite (write_valid _ _ Hm').
    move=> /= v1 Hv1.
    rewrite Fv.setP_neq in Hv1; last by rewrite vtype_diff.
    rewrite -(H' v1 Hv1).
    apply: (writeP_neq Hm').
    split.
    + by apply: is_align_no_overflow; apply: valid_align Hvmem.
    + by apply: is_align_no_overflow; apply: valid_align H.
    admit.
  Admitted.

  Lemma valid_stk_arr_stk s1 s2 sz vn n m' v0 i ofs (a: Array.array n (word sz)) t:
    let vi := {| vtype := sarr sz n; vname := vn |} in
    Mvar.get m.1 vi = Some ofs ->
    get_var (evm s1) vi = ok (Varr a) ->
    valid_pointer (emem s2) (pstk + wrepr _ (wsize_size sz * i + ofs)) sz ->
    write_mem (emem s2) (pstk + wrepr _ (wsize_size sz * i + ofs)) sz v0 = ok m' ->
    Array.set a i v0 = ok t ->
    valid_stk (evm s1) (emem s2) pstk ->
    valid_stk (evm s1).[vi <- ok t] m' pstk.
  Proof.
  move=> vi Hget Ha Hvmem Hm' Ht H x; have := H x.
  case Heq: Mvar.get => [ ptr | // ].
  case: x Heq => -[] // => [ sz' n' | sz' ] xn Heq /=.
  + exact: (valid_stk_arr_arr_stk Hget Heq Ha Hvmem Hm' Ht).
  exact: (valid_stk_word_arr_stk Hget Heq Ha Hvmem Hm' Ht).
  Qed.

  Lemma valid_arr_stk sz n vn v0 i ofs s1 s2 m' (a: Array.array n (word sz)) t:
    let vi := {| vtype := sarr sz n; vname := vn |} in
    Mvar.get m.1 vi = Some ofs ->
    get_var (evm s1) vi = ok (Varr a) ->
    write_mem (emem s2) (pstk + wrepr _ (wsize_size sz * i + ofs)) sz v0 = ok m' ->
    Array.set a i v0 = ok t ->
    valid s1 s2 ->
    valid {| emem := emem s1; evm := (evm s1).[vi <- ok t] |}
          {| emem := m'; evm := evm s2 |}.
  Proof.
    move => vi Hget Ha Hm' Ht.
    have Hvmem : valid_pointer (emem s2) (pstk + wrepr _ (wsize_size sz * i + ofs)) sz.
    + by apply/writeV; eauto.
    case => H1 H2 H3 H4 [H5 H6].
    split => //=.
    + move=> w Hvmem' Hv.
      rewrite (H2 _ Hvmem') //.
      symmetry; apply: (writeP_neq Hm').
      split.
      - by apply: is_align_no_overflow; apply: valid_align Hvmem.
      - by apply: is_align_no_overflow; apply: valid_align Hv.
      admit.
    + move=> w' sz'.
      by rewrite (write_valid _ _ Hm') H3.
    + move=> x Hx1 Hx2.
      rewrite Fv.setP_neq.
      apply: H4=> //.
      apply/negP=> /eqP Habs.
      by rewrite -Habs /is_in_stk Hget in Hx1.
    + split=> //.
      exact: (valid_stk_arr_stk Hget Ha Hvmem Hm' Ht).
  Admitted.

  Lemma get_var_arr n sz (a: Array.array n (word sz)) vm vi:
    get_var vm vi = ok (Varr a) ->
    exists vn, vi = {| vtype := sarr sz n; vname := vn |}.
  Proof.
    move: vi=> [vt vn] //=.
    apply: on_vuP=> //= x Hx; rewrite /to_val.
    move: vt x Hx=> [] // sz' n' /= x Hx /Varr_inj [-> [?]]; subst => /= ?.
    by exists vn.
  Qed.

  Lemma check_arr_stkW sz (vi vi': var_i) (s1 s2: estate) v v' e e':
    check_arr_stk m sz vi e vi' e' -> valid s1 s2 ->
    value_uincl v v' -> 
    forall s1', write_lval gd (Laset vi e) v s1 = ok s1' ->
    exists s2', write_lval gd (Lmem sz vi' e') v' s2 = ok s2' /\ valid s1' s2'.
  Proof.
    move: vi=> [vi vii].
    case/andP=> /eqP hvi' /=.
    case: vi => -[] //= sz' n vi /andP[] /eqP -> {sz'}.
    case Hget: Mvar.get => [ ofs | // ] /is_addr_ofsP [i] [? ?]; subst e e' => Hval Hv s1'.
    case: (Hval); rewrite -hvi' => H1 H2 H3 H4 [H5 H6].
    apply on_arr_varP => sz' n' t' [] ??; subst sz' n' => Ha.
    move => /=.
    apply: rbindP=> v0 Hv0.
    apply: rbindP=> t Ht.
    apply: rbindP=> vm.
    apply: set_varP => [varr /to_arr_ok /Varr_inj1 <- {varr} <- [] <-| _ /of_val_error] //=.
    rewrite (value_uincl_word Hv Hv0) H5 /=.
    rewrite /zero_extend !wrepr_unsigned.
    suff: exists m', write_mem (emem s2) (pstk + wrepr Uptr (wsize_size sz * i + ofs)) sz v0 = ok m'.
    - case => m' Hm'; rewrite Hm' /=; eexists; split; first by reflexivity.
      exact: (valid_arr_stk Hget Ha Hm' Ht Hval).
    apply/writeV.
    case: (validm Hget) => sx [[<-]] {sx} [hofs hofs' hal hdisj].
    have hi := Array.setP_inv Ht.
    rewrite H3; apply/orP; right; apply/andP; split.
    - admit.
    rewrite (proj2 pstk_add).
    - have : wrepr Uptr (wsize_size sz * i + ofs) = (wrepr _ (wsize_size sz * i) + wrepr _ ofs)%R.
      + admit.
      by move => ->; apply: is_align_array.
    have := wsize_size_pos sz; nia.
  Admitted.

  Lemma valid_stk_mem s1 s2 sz ptr off val m' m'2:
    write_mem (emem s1) (ptr + off) sz val = ok m' ->
    ~ between pstk stk_size (ptr + off) sz ->
    write_mem (emem s2) (ptr + off) sz val = ok m'2 ->
    valid_stk (evm s1) (emem s2) pstk ->
    valid_stk (evm s1) m'2 pstk.
  Proof.
    move=> Hm' Hbound Hm'2 Hv x.
    have Hvalid : valid_pointer (emem s1) (ptr + off) sz.
    - by apply/writeV; eauto.
    move: Hv=> /(_ x).
    case Hget: (Mvar.get m.1 x)=> [offx|//].
    move: x Hget=> [[| |sz' n|] vn] Hget //= H.
    + move=> off' Hoff'.
      move: H=> /(_ off' Hoff') [H H']; split.
      + by rewrite (write_valid _ _ Hm'2).
      move => t a Ht v0 Hv0.
      rewrite -(H' a Ht v0 Hv0).
      apply: (writeP_neq Hm'2).
      split.
      - by apply: is_align_no_overflow; apply: valid_align Hvalid.
      - by apply: is_align_no_overflow; apply: valid_align H.
      admit.
    case => [H'' H']; split.
    + by rewrite (write_valid _ _ Hm'2).
    move=> v0 Hv0.
    rewrite -(H' v0 Hv0).
    apply: (writeP_neq Hm'2).
    split.
    - by apply: is_align_no_overflow; apply: valid_align Hvalid.
    - by apply: is_align_no_overflow; apply: valid_align H''.
    admit.
  Admitted.

  (*
  Lemma valid_mem s1 s2 m' m'2 ptr off sz val:
    write_mem (emem s1) (ptr + off) sz val = ok m' ->
    write_mem (emem s2) (ptr + off) sz val = ok m'2 ->
    valid s1 s2 ->
    valid {| emem := m'; evm := evm s1 |} {| emem := m'2; evm := evm s2 |}.
  Proof.
    move=> Hm' Hm'2 [H1 H2 H3 H4 [H5 H6]].
    split=> //=.
    + move=> sz' w Hw.
      rewrite (write_valid _ _ Hm') in Hw.
      exact: H1.
    + move=> w sz' Hw.
      rewrite writeP_eq.
      apply: (read_mem_write_same Hm' Hm'2 H2).
      by rewrite (write_valid _ Hm').
    + move=> w.
      rewrite -(write_valid _ Hm') -(write_valid _ Hm'2).
      exact: H3.
    + split=> //.
      have Hvalid1: valid_addr (emem s1) (I64.add ptr off).
        apply/writeV; exists m'; exact: Hm'.
      exact: (valid_stk_mem Hm' Hvmem (H1 _ Hvalid1)).
  Qed.
*)

  Lemma check_memW sz (vi vi': var_i) (s1 s2: estate) v v' e e':
    check_var m vi vi' -> check_e m e e' -> valid s1 s2 -> 
    value_uincl v v' ->
    forall s1', write_lval gd (Lmem sz vi e) v s1 = ok s1'->
    exists s2', write_lval gd (Lmem sz vi' e') v' s2 = ok s2' /\ valid s1' s2'.
  Proof.
    move => Hvar He Hv Hu s1'.
    case: (Hv) => H1 H2 H3 H4 [H5 H6].
    rewrite /write_lval; t_xrbindP => ptr wi hwi hwiptr ofs we he heofs w hvw.
    move => m' Hm' <- {s1'}.
    have [wi' [-> hwi']] := check_varP Hvar H4 hwi.
    rewrite /= /to_pointer (value_uincl_word hwi' hwiptr) /=.
    have [we' [-> hwe']] := check_eP He Hv he.
    rewrite /= (value_uincl_word hwe' heofs) /= (value_uincl_word Hu hvw) /=.
    have : exists m2', write_mem (emem s2) (ptr + ofs) sz w = ok m2'.
    + by apply: writeV; rewrite H3; apply /orP; left; apply/writeV; eauto.
    case => m2' Hm2'; rewrite Hm2' /=; eexists; split; first by reflexivity.
    (* exact: (valid_mem Hm'). *)
  Admitted.

  Lemma check_arrW (vi vi': var_i) (s1 s2: estate) v v' e e':
    check_var m vi vi' -> check_e m e e' -> valid s1 s2 -> value_uincl v v' ->
    forall s1', write_lval gd (Laset vi e) v s1 = ok s1'->
    exists s2', write_lval gd (Laset vi' e') v' s2 = ok s2' /\ valid s1' s2'.
  Proof.
    case: vi vi' => vi ivi [vi' ivi'].
    move=> Hvar He Hv Hu s1'.
    have Hv' := Hv.
    move: Hv'=> [] H1 H2 H3 H4 [H5 H6].
    apply: rbindP=> [[]] // sz n a Ha.
    apply: rbindP=> i.
    apply: rbindP=> vali Hvali Hi.
    apply: rbindP=> v0 Hv0.
    apply: rbindP=> t Ht.
    apply: rbindP=> vm.
    rewrite /set_var;apply: set_varP => //=.
    + move=> varr Hvarr <- [] <- /=.
      have Hv'0 := value_uincl_word Hu Hv0.
      have [w [-> U]] := check_eP He Hv Hvali.
      have [??]:= value_uincl_int U Hi; subst vali w => /=.
      rewrite /= /on_arr_var.
      have [w [->]]:= check_varP Hvar H4 Ha.
      case: w => //= sz0 n0 a0 [?] [?]; subst => /= Ha0.
      have Hvar' := Hvar; move: Hvar'=> /andP [/andP [Hnotinstk /eqP /= Heq] notstk].
      subst vi'. rewrite Hv'0 /=.
      have [t' [-> Htt'] /=]:= Array_set_uincl Ha0 Ht.
      rewrite /set_var /=.
      have Utt': value_uincl (@Varr sz0 n0 t) (Varr t').
      - by split => //; exists erefl.
      have [varr' [-> Uarr] /=]:= of_val_uincl Utt' Hvarr.
      exists {| emem := emem s2; evm := (evm s2).[vi <- ok varr'] |}; split=> //.
      split=> //=.
      + exact: eq_vm_write.
      + split=> //.
      rewrite /get_var Fv.setP_neq //.
      exact: valid_stk_write_notinstk.
     move => _ H; exfalso; move: H.
    have [xn] := get_var_arr Ha.
    by case: vi {Hvar Ha} => -[]//= sz' n' xn'[] -> -> _ {sz' n' xn'}; rewrite eq_dec_refl pos_dec_n_n.
  Qed.

  Lemma check_lvalP (r1 r2: lval) v v' (s1 s2: estate) :
    check_lval m r1 r2 -> valid s1 s2 -> 
    value_uincl v v' ->
    forall s1', write_lval gd r1 v s1 = ok s1' ->
    exists s2', write_lval gd r2 v' s2 = ok s2' /\ valid s1' s2'.
  Proof.
    move=> Hr Hv Hu; move: Hr.
    case: r1=> [vi t |vi|sz vi e|vi e].
    + case: r2=> // vi' t' /= /eqP -> s1' H.
      have [-> _]:= write_noneP H.
      by rewrite (uincl_write_none _ Hu H); exists s2.      
    + case: r2=> // [vi'|sz' vi' e].
      + move=> /check_varW /(_ Hv) H s1' Hw.
        by move: (H _ _ Hu _ Hw)=> [s2' Hs2']; exists s2'.
      rewrite /write_lval /=.
      move=> /check_var_stkW /(_ Hv) H s1' Hw.
      by move: (H _ _ Hu _ Hw)=> [s2' Hs2']; exists s2'.
    + case: r2=> // sz' vi' e'.
      move=> /andP [/andP [] /eqP ? Hvar He] s1' Hw; subst sz'.
      by move: (check_memW Hvar He Hv Hu Hw)=> [s2' Hs2']; exists s2'.
    case: r2=> // [ sz' | ] vi' e'.
    move=> /check_arr_stkW /(_ Hv) H s1' Hw.
    move: (H _ _ Hu _ Hw)=> [s2' Hs2']; exists s2'=> //.
    move=> /andP [Hvar He] s1' Hw.
    move: (check_arrW Hvar He Hv Hu Hw)=> [s2' Hs2']; exists s2'=> //.
  Qed.

  Lemma check_lvalsP (r1 r2: lvals) vs vs' (s1 s2: estate) :
    all2 (check_lval m) r1 r2 -> valid s1 s2 ->
    List.Forall2 value_uincl vs vs' ->
    forall s1', write_lvals gd s1 r1 vs = ok s1' ->
    exists s2', write_lvals gd s2 r2 vs' = ok s2' /\ valid s1' s2'.
  Proof.
    elim: r1 r2 vs vs' s1 s2=> //= [|a l IH] [|a' l'] // [] //.
    + move=> vs' ? s2 ? Hvalid H;sinversion H => s1' [] <-.
      exists s2; split=> //.
    + move=> vsa vsl ? s1 s2 /andP [Hchecka Hcheckl] Hvalid H s1'.
      sinversion H.
      apply: rbindP=> x Ha Hl.
      move: (check_lvalP Hchecka Hvalid H2 Ha)=> [s3 [Hs3 Hvalid']].
      move: (IH _ _ _ _ _ Hcheckl Hvalid' H4 _ Hl)=> [s3' [Hs3' Hvalid'']].
      by exists s3'; split=> //=; rewrite Hs3.
  Qed.

  Let Pi_r s1 (i1:instr_r) s2 :=
    forall ii1 ii2 i2, check_i m (MkI ii1 i1) (MkI ii2 i2) ->
    forall s1', valid s1 s1' ->
    exists s2', S.sem_i SP gd s1' i2 s2' /\ valid s2 s2'.

  Let Pi s1 (i1:instr) s2 :=
    forall i2, check_i m i1 i2 ->
    forall s1', valid s1 s1' ->
    exists s2', S.sem_I SP gd s1' i2 s2' /\ valid s2 s2'.

  Let Pc s1 (c1:cmd) s2 :=
    forall c2, all2 (check_i m) c1 c2 ->
    forall s1', valid s1 s1' ->
    exists s2', S.sem SP gd s1' c2 s2' /\ valid s2 s2'.

  Let Pfor (i1: var_i) (vs: seq Z) (s1: estate) (c: cmd) (s2: estate) := True.

  Let Pfun (m1: mem) (fn: funname) (vargs: seq value) (m2: mem) (vres: seq value) := True.

  Local Lemma Hskip s: Pc s [::] s.
  Proof.
    move=> [] // => _ s' Hv.
    exists s'; split; [exact: S.Eskip|exact: Hv].
  Qed.

  Local Lemma Hcons s1 s2 s3 i c :
    sem_I P gd s1 i s2 ->
    Pi s1 i s2 -> sem P gd s2 c s3 -> Pc s2 c s3 -> Pc s1 (i :: c) s3.
  Proof.
    move=> _ Hi _ Hc [|i' c'] //= /andP [Hi'c Hc'c] s1' Hv.
    have [s2' [Hi' Hv2]] := Hi _ Hi'c _ Hv.
    have [s3' [Hc' Hv3]] := Hc _ Hc'c _ Hv2.
    exists s3'; split=> //.
    apply: S.Eseq; [exact: Hi'|exact: Hc'].
  Qed.

  Local Lemma HmkI ii i s1 s2 :
    sem_i P gd s1 i s2 -> Pi_r s1 i s2 -> Pi s1 (MkI ii i) s2.
  Proof. 
    move=> _ Hi [ii' ir'] Hc s1' Hv.
    move: Hi=> /(_ ii ii' ir' Hc s1' Hv) [s2' [Hs2'1 Hs2'2]].
    by exists s2'; split.
  Qed.

  Local Lemma Hassgn s1 s2 x tag e :
    Let v := sem_pexpr gd s1 e in write_lval gd x v s1 = Ok error s2 ->
    Pi_r s1 (Cassgn x tag e) s2.
  Proof.
    apply: rbindP=> v Hv Hw ii1 ii2 i2 Hi2 s1' Hvalid.
    case: i2 Hi2=> //= x' a e' /andP [Hlval He].
    have [v' [He' Uvv']] := (check_eP He Hvalid Hv).
    move: (check_lvalP Hlval Hvalid Uvv' Hw)=> [s2' [Hw' Hvalid']].
    exists s2'; split=> //.
    apply: S.Eassgn;by rewrite He'.
  Qed.

  Local Lemma Hopn s1 s2 t o xs es :
    sem_sopn gd o s1 xs es = ok s2 ->
    Pi_r s1 (Copn xs t o es) s2.
  Proof.
    apply: rbindP=> vs.
    apply: rbindP=> w He Hop Hw ii1 ii2 i2 Hi2 s1' Hvalid.
    case: i2 Hi2=> //= xs' t' o' es' /andP [/andP [Hlvals /eqP Ho] Hes].
    have [vs' [He' Uvv']] := (check_esP Hes Hvalid He);subst o'.
    have [w' [Hop' Uww']]:= vuincl_exec_opn Uvv' Hop.
    have [s2' [Hw' Hvalid']] := check_lvalsP Hlvals Hvalid Uww' Hw.
    exists s2'; split=> //.
    by apply: S.Eopn;rewrite /sem_sopn He' /= Hop'.
  Qed.

  Local Lemma Hif_true s1 s2 e c1 c2 :
    Let x := sem_pexpr gd s1 e in to_bool x = Ok error true ->
    sem P gd s1 c1 s2 -> Pc s1 c1 s2 -> Pi_r s1 (Cif e c1 c2) s2.
  Proof.
    apply: rbindP=> v Hv Htrue ? Hc ii1 ii2 i2 Hi2 s1' Hvalid.
    case: i2 Hi2=> //= e' c1' c2' /andP [/andP [He Hcheck] _].
    move: (Hc _ Hcheck _ Hvalid)=> [s2' [Hsem Hvalid']].
    exists s2'; split=> //.
    apply: S.Eif_true=> //.
    have [v' [-> ]]:= check_eP He Hvalid Hv.
    by move=> /value_uincl_bool -/(_ _ Htrue) [_ ->].
  Qed.

  Local Lemma Hif_false s1 s2 e c1 c2 :
    Let x := sem_pexpr gd s1 e in to_bool x = Ok error false ->
    sem P gd s1 c2 s2 -> Pc s1 c2 s2 -> Pi_r s1 (Cif e c1 c2) s2.
  Proof.
    apply: rbindP=> v Hv Hfalse ? Hc ii1 ii2 i2 Hi2 s1' Hvalid.
    case: i2 Hi2=> //= e' c1' c2' /andP [/andP [He _] Hcheck].
    move: (Hc _ Hcheck _ Hvalid)=> [s2' [Hsem Hvalid']].
    exists s2'; split=> //.
    apply: S.Eif_false=> //.
    have [v' [-> ]]:= check_eP He Hvalid Hv.
    by move=> /value_uincl_bool -/(_ _ Hfalse) [_ ->].
  Qed.

  Local Lemma Hwhile_true s1 s2 s3 s4 c e c' :
    sem P gd s1 c s2 -> Pc s1 c s2 ->
    Let x := sem_pexpr gd s2 e in to_bool x = ok true ->
    sem P gd s2 c' s3 -> Pc s2 c' s3 ->
    sem_i P gd s3 (Cwhile c e c') s4 -> Pi_r s3 (Cwhile c e c') s4 -> Pi_r s1 (Cwhile c e c') s4.
  Proof.
    move=> _ Hc.
    apply: rbindP=> v Hv Htrue ? Hc' ? Hwhile ii1 ii2 i2 Hi2 s1' Hvalid.
    case: i2 Hi2=> //= c2 e2 c2' /andP [/andP [Hc2 He2] Hc2'].
    move: (Hc _ Hc2 _ Hvalid)=> [s2' [Hsem' Hvalid']].
    move: (Hc' _ Hc2' _ Hvalid')=> [s2'' [Hsem'' Hvalid'']].
    have [|s3' [Hsem''' Hvalid''']] := (Hwhile ii1 ii2 (Cwhile c2 e2 c2') _ _ Hvalid'').
    by rewrite /= Hc2 He2 Hc2'.
    exists s3'; split=> //.
    apply: S.Ewhile_true; eauto.
    have [v' [-> ]]:= check_eP He2 Hvalid' Hv.
    by move=> /value_uincl_bool -/(_ _ Htrue) [_ ->].
  Qed.

  Local Lemma Hwhile_false s1 s2 c e c' :
    sem P gd s1 c s2 -> Pc s1 c s2 ->
    Let x := sem_pexpr gd s2 e in to_bool x = ok false ->
    Pi_r s1 (Cwhile c e c') s2.
  Proof.
    move=> _ Hc.
    apply: rbindP=> v Hv Hfalse ii1 ii2 i2 Hi2 s1' Hvalid.
    case: i2 Hi2=> //= c2 e2 c2' /andP [/andP [Hc2 He2] _].
    move: (Hc _ Hc2 _ Hvalid)=> [s2' [Hsem' Hvalid']].
    exists s2'; split=> //.
    apply: S.Ewhile_false; eauto.
    have [v' [-> ]]:= check_eP He2 Hvalid' Hv.
    by move=> /value_uincl_bool -/(_ _ Hfalse) [_ ->].
  Qed.

  Local Lemma Hfor s1 s2 (i:var_i) d lo hi c vlo vhi :
    Let x := sem_pexpr gd s1 lo in to_int x = Ok error vlo ->
    Let x := sem_pexpr gd s1 hi in to_int x = Ok error vhi ->
    sem_for P gd i (wrange d vlo vhi) s1 c s2 ->
    Pfor i (wrange d vlo vhi) s1 c s2 -> Pi_r s1 (Cfor i (d, lo, hi) c) s2.
  Proof. by []. Qed.

  Local Lemma Hfor_nil s i c: Pfor i [::] s c s.
  Proof. by []. Qed.

  Local Lemma Hfor_cons s1 s1' s2 s3 (i : var_i) (w:Z) (ws:seq Z) c :
    write_var i w s1 = Ok error s1' ->
    sem P gd s1' c s2 ->
    Pc s1' c s2 ->
    sem_for P gd i ws s2 c s3 -> Pfor i ws s2 c s3 -> Pfor i (w :: ws) s1 c s3.
  Proof. by []. Qed.

  Local Lemma Hcall s1 m2 s2 ii xs fn args vargs vs:
    sem_pexprs gd s1 args = Ok error vargs ->
    sem_call P gd (emem s1) fn vargs m2 vs ->
    Pfun (emem s1) fn vargs m2 vs ->
    write_lvals gd {| emem := m2; evm := evm s1 |} xs vs = Ok error s2 ->
    Pi_r s1 (Ccall ii xs fn args) s2.
  Proof. by []. Qed.

  Local Lemma Hproc m1 m2 fn f vargs s1 vm2 vres:
    get_fundef P fn = Some f ->
    write_vars (f_params f) vargs {| emem := m1; evm := vmap0 |} = ok s1 ->
    sem P gd s1 (f_body f) {| emem := m2; evm := vm2 |} ->
    Pc s1 (f_body f) {| emem := m2; evm := vm2 |} ->
    mapM (fun x : var_i => get_var vm2 x) (f_res f) = ok vres ->
    List.Forall is_full_array vres ->
    Pfun m1 fn vargs m2 vres.
  Proof. by []. Qed.

  Lemma check_cP s1 c s2: sem P gd s1 c s2 -> Pc s1 c s2.
  Proof.
    apply (@sem_Ind P gd Pc Pi_r Pi Pfor Pfun Hskip Hcons HmkI Hassgn Hopn
             Hif_true Hif_false Hwhile_true Hwhile_false Hfor Hfor_nil Hfor_cons Hcall Hproc).
  Qed.
End PROOF.

Lemma init_mapP nstk l sz m m1 m2 :
  Memory.alloc_stack m1 sz = ok m2 ->
  init_map sz nstk l = ok m -> 
  valid_map m sz /\ m.2 = nstk.
Proof.
  move=> /Memory.alloc_stackP [Hadd Hread Hval Hbound].
  rewrite /init_map.
  set f1 := (f in foldM f _ _ ).
  set g := (g in foldM _ _ _ >>= g). 
  have : forall p p',
    foldM f1 p l = ok p' -> 
    valid_map (p.1,nstk) p.2 -> 0 <= p.2 ->
    (forall y py sy, Mvar.get p.1 y = Some py ->
        size_of (vtype y) = ok sy -> py + sy <= p.2) ->
    (p.2 <= p'.2 /\
        valid_map (p'.1, nstk) p'.2).
  + elim:l => [|[v pn] l Hrec] p p'//=.
    + by move=>[] <- ???;split=>//;omega.
    case:ifPn=> //= /Z.leb_le Hle.
    case: ifP => // Hal.
    case Hs : size_of=> [svp|]//= /Hrec /= {Hrec}Hrec H2 H3 H4. 
    have Hpos := size_of_pos Hs.
    case:Hrec.
    + move=> x px;rewrite Mvar.setP;case:ifPn => /eqP Heq.
      + move=> [] ?;subst;exists svp;split=>//;split => //.
        + omega. + omega.
        move=> y py sy Hne.
        by rewrite Mvar.setP_neq // => /H4 H /H ?;omega.
      move=> /H2 [sx] [Hsx] [] Hle0 Hpx Hal' Hy;exists sx;split=>//;split=>//.
      + omega.
      move=> y py sy Hne;rewrite Mvar.setP;case:eqP=> [?[]? |].
      + subst;rewrite Hs => -[] ?;subst; omega.
      by move=> Hney;apply Hy.
    + omega.
    + move=> y py sy;rewrite Mvar.setP;case:eqP=> [?[]?|].
      + subst;rewrite Hs => -[] ->;omega.
      move=> ? /H4 H /H ?;omega.
    move=> Hle2 H';split=>//;first by omega.
  move=> H;case Heq : foldM => [p'|]//=.
  case: (H _ _ Heq)=> //= Hp' Hv.
  rewrite /g;case:ifP => //= /Z.leb_le Hp Hq Hr Hs [<-].
  split=>// x px Hx.
  case :(Hv x px Hx) => //= sx [] Hsx [] H1 H2 H3.
  by exists sx;split=>//;split=>//;omega.
Qed.

Import Memory.

Lemma check_fdP (P: prog) (gd: glob_defs) (SP: sprog) l fn fn' fd fd':
  get_fundef P fn = Some fd ->
  get_fundef SP fn' = Some fd' ->
  check_fd l fd fd' ->
  forall m1 va m1' vr, 
    sem_call P gd m1 fn va m1' vr ->
    (exists p, Memory.alloc_stack m1 (sf_stk_sz fd') = ok p) ->
    S.sem_call SP gd m1 fn' va m1' vr.
Proof.
  move=> get Sget.
  rewrite /check_fd.
  case Hinit: init_map => [m|] //= /andP[]/andP[] Hp Hr Hi.
  move=> m1 va m1' vr H [m2 Halloc]; sinversion H.
  have Hf: Some f = Some fd.
    by rewrite -get -H0.
  move: Hf=> [] Hf.
  subst f.
  have [/= Hv Hestk] := init_mapP Halloc Hinit.
  have Hstk: stk_ok (top_stack m2) (sf_stk_sz fd').
    by move: Halloc=> /alloc_stackP [].
  have Hval'': valid m (sf_stk_sz fd') (top_stack m2) {| emem := m1; evm := vmap0 |} {| emem := m2; evm := vmap0.[{| vtype := sword Uptr; vname := sf_stk_id fd' |} <- ok (top_stack m2)] |}.
    move: Halloc=> /alloc_stackP [] Ha1 Ha2 Ha3 Ha4 Ha5 Ha6 Ha7.
    split=> //=.
    + admit.
    + move=> x.
      case Heq: (x == {| vtype := sword Uptr; vname := sf_stk_id fd' |}).
      + move: Heq=> /eqP -> /=.
        rewrite /is_vstk /vstk.
        by rewrite Hestk eq_refl.
      + rewrite Fv.setP_neq=> //.
        apply/eqP=> Habs.
        by rewrite Habs eq_refl in Heq.
    + split.
      by rewrite /vstk Hestk /= /get_var Fv.setP_eq.
      move=> x.
      case Hget: (Mvar.get m.1 x)=> [a|//].
      case Htype: (vtype x)=> [| |sz n| sz] //.
      + move=> off Hoff; split.
        rewrite Ha3.
        apply/orP; right.
        admit.
        admit.
      admit.
        (*
        rewrite -!add_repr_r.
        have Hx: x = {| vtype := sarr n; vname := vname x |}.
          case: x Hget Htype=> [vt vn] Hget Htype /=.
          by rewrite -Htype.
        rewrite Hx in Hget.
        apply: (valid_get_a_off _ Hv Hget)=> //.
        rewrite /vmap0=> a0 Habs v Habs'; exfalso.
        rewrite /Fv.get /= in Habs.
        move: Habs=> [] Habs.
        rewrite -Habs in Habs'.
        by rewrite /FArray.get /Array.empty /FArray.cnst /= in Habs'.
      + split.
        rewrite Ha3.
        apply/orP; right.
        rewrite -!add_repr_r.
        have Hx: x = {| vtype := sword; vname := vname x |}.
          case: x Hget Htype=> [vt vn] Hget Htype /=.
          by rewrite -Htype.
        rewrite Hx in Hget.
        apply: (valid_get_w _ Hv Hget)=> //.
        rewrite /vmap0 /= /Fv.empty /= => v Habs.
        by rewrite /Fv.get /= in Habs.
         *)
  have := check_varsW Hp Hval'' _ H1.
  move=> /(_ va) [ |s2 [Hs2 Hv2]];first by apply List_Forall2_refl.
  have [[m2' vm2'] [Hs2' Hv2']] := check_cP SP Hstk Hv H2 Hi Hv2.
  apply: S.EcallRun; eauto=> //.
  + admit.
  + move: Hv2'=> [] _ _ _ Heqvm _.
    have [vr' [/= ->]] := check_varsP Hr Heqvm H3.
    by move=> /(is_full_array_uincls H4) ->.
  + (* apply eq_memP=> w.
    pose sz := sf_stk_sz fd'.
    have -> := @free_stackP m2' (free_stack m2' pstk sz) pstk sz (erefl _) w.
    case Hv2' => /=;rewrite /disjoint_stk => Hdisj Hmem Hvalw _ _.
    move: (Hdisj w) (Hmem w) (Hvalw w)=> {Hdisj Hmem Hvalw} Hdisjw Hmemw Hvalw.
    case Heq1: (read_mem m1' w) => [w'|].
    + have Hw : valid_addr m1' w by apply /readV;exists w'.
      have -> : ((pstk <=? w) && (w <? pstk + sz))=false. 
      + by apply /negbTE /negP => /andP[] /Z.leb_le ? /Z.ltb_lt ?;apply Hdisjw.
      by rewrite -Heq1;apply Hmemw.
    have ? := read_mem_error Heq1;subst;case:ifP=> Hbound //.
    case Heq2: (read_mem m2' w) => [w'|];last by rewrite (read_mem_error Heq2).
    have : valid_addr m2' w by apply /readV;exists w'.
    by rewrite Hvalw Hbound orbC /= => /readV [w1];rewrite Heq1.
  *)
Admitted.

Definition alloc_ok SP fn m1 :=
  forall fd, get_fundef SP fn = Some fd ->
  exists p, Memory.alloc_stack m1 (sf_stk_sz fd) = ok p.

Lemma check_progP (P: prog) (gd: glob_defs) (SP: sprog) l fn:
  check_prog P SP l ->
  forall m1 va m1' vr, 
    sem_call P gd m1 fn va m1' vr ->
    alloc_ok SP fn m1 ->
    S.sem_call SP gd m1 fn va m1' vr.
Proof.
  move=> Hcheck m1 va m1' vr H Halloc.
  have H' := H; sinversion H'.
  move: (all_progP Hcheck H0)=> [fd' [l' [Hfd' Hl']]].
  by apply: check_fdP=> //; eauto.
Qed.
