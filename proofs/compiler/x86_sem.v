(* -------------------------------------------------------------------- *)
From mathcomp Require Import all_ssreflect all_algebra.
Require oseq.
Require Import low_memory word expr psem.
Import Utf8 Relation_Operators.
Import Memory.

Set   Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

(* ==================================================================== *)
Definition label := positive.

(* -------------------------------------------------------------------- *)
Variant register : Type :=
  | RAX | RCX | RDX | RBX | RSP | RBP | RSI | RDI
  | R8  | R9  | R10 | R11 | R12 | R13 | R14 | R15.

(* -------------------------------------------------------------------- *)
Variant rflag : Type := CF | PF | ZF | SF | OF | DF.

(* -------------------------------------------------------------------- *)
Variant scale : Type := Scale1 | Scale2 | Scale4 | Scale8.

(* -------------------------------------------------------------------- *)
(* disp + base + scale × offset *)
Record address : Type := mkAddress {
  ad_disp   : pointer;
  ad_base   : option register;
  ad_scale  : scale;
  ad_offset : option register;
}.

(* -------------------------------------------------------------------- *)
Variant oprd : Type :=
| Imm_op     of u64
| Glo_op     of global
| Reg_op     of register
| Adr_op     of address.

Definition string_of_oprd (o: oprd) : string :=
  match o with
  | Imm_op x => "Imm"
  | Glo_op x => "Glo"
  | Reg_op x => "Reg"
  | Adr_op x => "Adr"
  end.

(* -------------------------------------------------------------------- *)
Variant ireg : Type :=
| Imm_ir of u64
| Reg_ir of register.

(* -------------------------------------------------------------------- *)
Variant condt : Type :=
| O_ct                  (* overflow *)
| NO_ct                 (* not overflow *)
| B_ct                  (* below, not above or equal *)
| NB_ct                 (* not below, above or equal *)
| E_ct                  (* equal, zero *)
| NE_ct                 (* not equal, not zero *)
| BE_ct                 (* below or equal, not above *)
| NBE_ct                (* not below or equal, above *)
| S_ct                  (* sign *)
| NS_ct                 (* not sign *)
| P_ct                  (* parity, parity even *)
| NP_ct                 (* not parity, parity odd *)
| L_ct                  (* less than, not greater than or equal to *)
| NL_ct                 (* not less than, greater than or equal to *)
| LE_ct                 (* less than or equal to, not greater than *)
| NLE_ct                (* not less than or equal to, greater than *).

Definition string_of_condt (c: condt) : string :=
  match c with
  | O_ct => "O"
  | NO_ct => "NO"
  | B_ct => "B"
  | NB_ct => "NB"
  | E_ct => "E"
  | NE_ct => "NE"
  | BE_ct => "BE"
  | NBE_ct => "NBE"
  | S_ct => "S"
  | NS_ct => "NS"
  | P_ct => "P"
  | NP_ct => "NP"
  | L_ct => "L"
  | NL_ct => "NL"
  | LE_ct => "LE"
  | NLE_ct => "NLE"
  end.

(* -------------------------------------------------------------------- *)
Variant asm : Type :=
| LABEL of label

  (* Data transfert *)
| MOV    of wsize & oprd & oprd    (* copy *)
| CMOVcc of wsize & condt & oprd & oprd    (* conditional copy *)

  (* Arithmetic *)
| ADD    of wsize & oprd & oprd            (* add unsigned / signed *)
| SUB    of wsize & oprd & oprd            (* sub unsigned / signed *)
| MUL    of wsize & oprd                   (* mul unsigned *)
| IMUL   of wsize & oprd & option (oprd * option u32)
                                           (* mul signed with truncation *)
| DIV    of wsize & oprd                   (* div unsigned *)
| IDIV   of wsize & oprd                   (* div   signed *)

| ADC    of wsize & oprd & oprd            (* add with carry *)
| SBB    of wsize & oprd & oprd            (* sub with borrow *)

| NEG	 of wsize & oprd	(* negation *)

| INC    of wsize & oprd                   (* increment *)
| DEC    of wsize & oprd                   (* decrement *)

  (* Flag *)
| SETcc  of condt & oprd                   (* Set byte on condition *)
| BT     of wsize & oprd & ireg            (* Bit test, sets result to CF *)

  (* Pointer arithmetic *)
| LEA    of wsize & register & oprd        (* Load Effective Address *)

  (* Comparison *)
| TEST   of wsize & oprd & oprd            (* Bit-wise logical and CMP *)
| CMP    of wsize & oprd & oprd            (* Signed sub CMP *)

  (* Jumps *)
| JMP    of label                          (* Unconditional jump *)
| Jcc    of label & condt                  (* Conditional jump *)

  (* Bitwise logical instruction *)
| AND    of wsize & oprd & oprd            (* bit-wise and *)
| OR     of wsize & oprd & oprd            (* bit-wise or  *)
| XOR    of wsize & oprd & oprd            (* bit-wise xor *)
| NOT    of wsize & oprd                   (* bit-wise not *)

  (* Bit shifts *)
| ROR    of wsize & oprd & ireg (* rotation / right *)
| ROL    of wsize & oprd & ireg (* rotation / left *)
| SHL    of wsize & oprd & ireg            (* unsigned / left  *)
| SHR    of wsize & oprd & ireg            (* unsigned / right *)
| SAL    of wsize & oprd & ireg            (*   signed / left; synonym of SHL *)
| SAR    of wsize & oprd & ireg            (*   signed / right *)
| SHLD   of wsize & oprd & register & ireg (* unsigned (double) / left *)
.

(* -------------------------------------------------------------------- *)
Scheme Equality for register.
Scheme Equality for rflag.
Scheme Equality for scale.
Scheme Equality for condt.

Definition reg_eqMixin := comparableClass register_eq_dec.
Canonical reg_eqType := EqType register reg_eqMixin.

Definition rflag_eqMixin := comparableClass rflag_eq_dec.
Canonical rflag_eqType := EqType rflag rflag_eqMixin.

Definition scale_eqMixin := comparableClass scale_eq_dec.
Canonical scale_eqType := EqType scale scale_eqMixin.

Definition address_beq (addr1: address) addr2 :=
  match addr1, addr2 with
  | mkAddress d1 b1 s1 o1, mkAddress d2 b2 s2 o2 =>
    [&& d1 == d2, b1 == b2, s1 == s2 & o1 == o2]
  end.

Lemma address_eq_axiom : Equality.axiom address_beq.
Proof.
case=> [d1 b1 s1 o1] [d2 b2 s2 o2]; apply: (iffP idP) => /=.
+ by case/and4P; do 4! move/eqP=> ->.
by case; do 4! move=> ->; rewrite !eqxx.
Qed.

Definition address_eqMixin := Equality.Mixin address_eq_axiom.
Canonical address_eqType := EqType address address_eqMixin.

Definition oprd_beq (op1 op2 : oprd) :=
  match op1, op2 with
  | Imm_op w1, Imm_op w2 => w1 == w2
  | Glo_op g1, Glo_op g2 => g1 == g2
  | Reg_op r1, Reg_op r2 => r1 == r2
  | Adr_op a1, Adr_op a2 => a1 == a2
  | _        , _         => false
  end.

Lemma oprd_eq_axiom : Equality.axiom oprd_beq.
Proof.
case=> [w1| g1 |r1|a1] [w2| g2 |r2|a2] /=; try constructor => //;
  by apply (equivP eqP); split=> [->|[]].
Qed.

Definition oprd_eqMixin := Equality.Mixin oprd_eq_axiom.
Canonical oprd_eqType := EqType oprd oprd_eqMixin.

Definition condt_eqMixin := comparableClass condt_eq_dec.
Canonical condt_eqType := EqType condt condt_eqMixin.

(* -------------------------------------------------------------------- *)
Definition registers :=
  [:: RAX; RCX; RDX; RBX; RSP; RBP; RSI; RDI ;
      R8 ; R9 ; R10; R11; R12; R13; R14; R15 ].

Lemma registers_fin_axiom : Finite.axiom registers.
Proof. by case. Qed.

Definition reg_choiceMixin :=
  PcanChoiceMixin (FinIsCount.pickleK registers_fin_axiom).
Canonical reg_choiceType :=
  Eval hnf in ChoiceType register reg_choiceMixin.

Definition reg_countMixin :=
  PcanCountMixin (FinIsCount.pickleK registers_fin_axiom).
Canonical reg_countType :=
  Eval hnf in CountType register reg_countMixin.

Definition reg_finMixin :=
  FinMixin registers_fin_axiom.
Canonical reg_finType :=
  Eval hnf in FinType register reg_finMixin.

(* -------------------------------------------------------------------- *)
Definition rflags := [:: CF; PF; ZF; SF; OF; DF].

Lemma rflags_fin_axiom : Finite.axiom rflags.
Proof. by case. Qed.

Definition rflag_choiceMixin :=
  PcanChoiceMixin (FinIsCount.pickleK rflags_fin_axiom).
Canonical rflag_choiceType :=
  Eval hnf in ChoiceType rflag rflag_choiceMixin.

Definition rflag_countMixin :=
  PcanCountMixin (FinIsCount.pickleK rflags_fin_axiom).
Canonical rflag_countType :=
  Eval hnf in CountType rflag rflag_countMixin.

Definition rflag_finMixin :=
  FinMixin rflags_fin_axiom.
Canonical rflag_finType :=
  Eval hnf in FinType rflag rflag_finMixin.

(* -------------------------------------------------------------------- *)
Module RegMap.
  Definition map := {ffun register -> u64}.

  Definition set (m : map) (x : register) (y : u64) : map :=
    [ffun z => if (z == x) then y else m z].
End RegMap.

(* -------------------------------------------------------------------- *)
Module RflagMap.
  Variant rflagv := Def of bool | Undef.

  Definition map := {ffun rflag -> rflagv}.

  Definition set (m : map) (x : rflag) (y : bool) : map :=
    [ffun z => if (z == x) then Def y else m z].

  Definition oset (m : map) (x : rflag) (y : rflagv) : map :=
    [ffun z => if (z == x) then y else m z].

  Definition update (m : map) (f : rflag -> option rflagv) : map :=
    [ffun rf => odflt (m rf) (f rf)].
End RflagMap.

(* -------------------------------------------------------------------- *)
Notation regmap   := RegMap.map.
Notation rflagmap := RflagMap.map.
Notation Def      := RflagMap.Def.
Notation Undef    := RflagMap.Undef.

Definition regmap0   : regmap   := [ffun x => 0%R].
Definition rflagmap0 : rflagmap := [ffun x => Undef].

Scheme Equality for RflagMap.rflagv.

Definition rflagv_eqMixin := comparableClass rflagv_eq_dec.
Canonical rflagv_eqType := EqType _ rflagv_eqMixin.

(* -------------------------------------------------------------------- *)
Record x86_mem : Type :=
  X86Mem {
      xmem : mem;
      xreg : regmap;
      xrf  : rflagmap;
    }.

Record x86_state := X86State {
  xm   :> x86_mem;
  xc   : seq asm;
  xip  : nat;
}.

Notation x86_result := (result error x86_mem).
Notation x86_result_state := (result error x86_state).

(* -------------------------------------------------------------------- *)
Section GLOB_DEFS.

Context (gd: glob_defs).

(* -------------------------------------------------------------------- *)

Definition mask_word (sz:wsize) : u64 := 
  match sz with
  | U8 | U16 => wshl (wrepr _ (-1)) (wsize_bits sz)
  | _ => 0%R
  end.

Definition merge_word (wr: u64) (sz:wsize) (w:word sz) := 
   wxor (wand (mask_word sz) wr) (zero_extend U64 w).

Definition word_extend_reg (r: register) sz (w: word sz) (m: x86_mem) := 
  merge_word (m.(xreg) r) w.
    
Definition mem_write_reg (r: register) sz (w: word sz) (m: x86_mem) :=  
  {|
    xmem := m.(xmem);
    xreg := RegMap.set m.(xreg) r (word_extend_reg r w m);
    xrf  := m.(xrf);
  |}.

Definition st_write_reg (r : register) sz (w : word sz) (s : x86_state) :=
  {| xm := mem_write_reg r w s;
     xc   := s.(xc);
     xip  := s.(xip); |}.

(* -------------------------------------------------------------------- *)
Definition st_get_rflag (rf : rflag) (s : x86_mem) :=
  if s.(xrf) rf is Def b then ok b else undef_error.

(* -------------------------------------------------------------------- *)
Definition mem_set_rflags (rf : rflag) (b : bool) (s : x86_mem) :=
  {|
    xmem := s.(xmem);
    xreg := s.(xreg);
    xrf  := RflagMap.set s.(xrf) rf b;
  |}.

Definition mem_unset_rflags (rf : rflag) (s : x86_mem) :=
  {|
    xmem := s.(xmem);
    xreg := s.(xreg);
    xrf  := RflagMap.oset s.(xrf) rf Undef;
  |}.

Definition st_set_rflags (rf : rflag) (b : bool) (s : x86_state) :=
  {| xm := mem_set_rflags rf b s;
     xc   := s.(xc);
     xip  := s.(xip); |}.

(* -------------------------------------------------------------------- *)
Definition mem_update_rflags f (s : x86_mem) :=
  {| xmem := s.(xmem);
     xreg := s.(xreg);
     xrf  := RflagMap.update s.(xrf) f;
     |}.

Definition st_update_rflags f (s : x86_state) :=
  {| xm := mem_update_rflags f s;
     xc   := s.(xc);
     xip  := s.(xip); |}.

(* -------------------------------------------------------------------- *)
Definition mem_write_mem (l : pointer) sz (w : word sz) (s : x86_mem) :=
  Let m := write_mem s.(xmem) l sz w in ok
  {| xmem := m;
     xreg := s.(xreg);
     xrf  := s.(xrf);
  |}.

Definition st_write_mem (l : pointer) sz (w : word sz ) (s : x86_state) :=
  Let m := mem_write_mem l w s in ok
  {| xm := m;
     xc   := s.(xc);
     xip  := s.(xip); |}.

(* -------------------------------------------------------------------- *)
Definition st_write_ip (ip : nat) (s : x86_state) :=
  {| xm := s.(xm);
     xc   := s.(xc);
     xip  := ip; |}.

(* -------------------------------------------------------------------- *)
Coercion word_of_scale (s : scale) : pointer :=
  wrepr Uptr match s with
  | Scale1 => 1
  | Scale2 => 2
  | Scale4 => 4
  | Scale8 => 8
  end.

(* -------------------------------------------------------------------- *)
Definition decode_addr (s : x86_mem) (a : address) : pointer := nosimpl (
  let: disp   := a.(ad_disp) in
  let: base   := odflt 0%R (omap (s.(xreg)) a.(ad_base)) in
  let: scale  := word_of_scale a.(ad_scale) in
  let: offset := odflt 0%R (omap (s.(xreg)) a.(ad_offset)) in
  disp + base + scale * offset)%R.

(* -------------------------------------------------------------------- *)
Definition write_oprd (o : oprd) sz (w : word sz) (s : x86_mem) :=
  match o with
  | Glo_op _
  | Imm_op _ => type_error
  | Reg_op r => ok (mem_write_reg r w s)
  | Adr_op a => mem_write_mem (decode_addr s a) w s
  end.

(* -------------------------------------------------------------------- *)
Definition read_oprd sz (o : oprd) (s : x86_mem) :=
  match o with
  | Imm_op v => ok (zero_extend sz v)
  | Glo_op g => if get_global_word gd g is Some v then ok (zero_extend sz v) else type_error
  | Reg_op r => ok (zero_extend sz (s.(xreg) r))
  | Adr_op a => read_mem s.(xmem) (decode_addr s a) sz
  end.

(* -------------------------------------------------------------------- *)
Definition read_ireg sz (ir : ireg) (s : x86_mem) :=
  zero_extend sz match ir with
  | Imm_ir v => v
  | Reg_ir r => s.(xreg) r
  end.

(* -------------------------------------------------------------------- *)
Definition eval_cond (c : condt) (rm : rflagmap) :=
  let get rf :=
    if rm rf is Def b then ok b else undef_error in

  match c with
  | O_ct   => get OF
  | NO_ct  => Let b := get OF in ok (~~ b)
  | B_ct   => get CF
  | NB_ct  => Let b := get CF in ok (~~ b)
  | E_ct   => get ZF
  | NE_ct  => Let b := get ZF in ok (~~ b)
  | S_ct   => get SF
  | NS_ct  => Let b := get SF in ok (~~ b)
  | P_ct   => get PF
  | NP_ct  => Let b := get PF in ok (~~ b)

  | BE_ct =>
      Let cf := get CF in
      Let zf := get ZF in ok (cf || zf)

  | NBE_ct =>
      Let cf := get CF in
      Let zf := get ZF in ok (~~ cf && ~~ zf)

  | L_ct =>
      Let sf  := get SF in
      Let of_ := get OF in ok (sf != of_)

  | NL_ct =>
      Let sf  := get SF in
      Let of_ := get OF in ok (sf == of_)

  | LE_ct =>
      Let zf  := get ZF in
      Let sf  := get SF in
      Let of_ := get OF in ok (zf || (sf != of_))

  | NLE_ct =>
      Let zf  := get ZF in
      Let sf  := get SF in
      Let of_ := get OF in ok (~~ zf && (sf == of_))
  end.

(* -------------------------------------------------------------------- *)
Definition is_label (lbl: label) (i: asm) : bool :=
  match i with
  | LABEL lbl' => lbl == lbl'
  | _ => false
  end.

(* -------------------------------------------------------------------- *)
Definition find_label (lbl : label) (a : seq asm) :=
  let idx := seq.find (is_label lbl) a in
  if idx < size a then ok idx else type_error.

(* -------------------------------------------------------------------- *)
Definition SF_of_word sz (w : word sz) :=
  msb w.

(* -------------------------------------------------------------------- *)
Definition PF_of_word sz (w : word sz) :=
  lsb w.

(* -------------------------------------------------------------------- *)
Definition ZF_of_word sz (w : word sz) :=
  w == 0%R.

(* -------------------------------------------------------------------- *)
Definition rflags_of_bwop sz (w : word sz) := fun rf =>
  match rf with
  | OF => Some (Def false)
  | CF => Some (Def false)
  | SF => Some (Def (SF_of_word w))
  | PF => Some (Def (PF_of_word w))
  | ZF => Some (Def (ZF_of_word w))
  | DF => None
  end.

(* -------------------------------------------------------------------- *)
Definition rflags_of_aluop sz (w : word sz) (vu vs : Z) := fun rf =>
  match rf with
  | OF => Some (Def (wsigned   w != vs))
  | CF => Some (Def (wunsigned w != vu))
  | SF => Some (Def (SF_of_word w))
  | PF => Some (Def (PF_of_word w))
  | ZF => Some (Def (ZF_of_word w))
  | DF => None
  end.

(* -------------------------------------------------------------------- *)
Definition rflags_of_aluop_nocf sz (w : word sz) (vs : Z) := fun rf =>
  match rf with
  | CF => None
  | OF => Some (Def (wsigned w != vs))
  | SF => Some (Def (SF_of_word w))
  | PF => Some (Def (PF_of_word w))
  | ZF => Some (Def (ZF_of_word w))
  | DF => None
  end.

(* --------------------------------------------------------------------- *)
Definition rflags_of_mul (ov : bool) := fun rf =>
  match rf with
  | SF | ZF | PF => Some Undef
  | OF | CF => Some (Def ov)
  | DF => None
  end.

(* --------------------------------------------------------------------- *)
Definition rflags_of_div := fun rf =>
  match rf with
  | SF | ZF | PF | OF | CF => Some Undef
  | DF => None
  end.

(* -------------------------------------------------------------------- *)

Definition rflags_of_sh (i:u8) of_ sz(r:word sz) rc := fun rf =>
  match rf with
  | OF => Some (if (i == 1)%R then Def of_ else Undef)
  | CF => Some (Def rc)
  | SF => Some (Def (SF_of_word r))
  | PF => Some (Def (PF_of_word r))
  | ZF => Some (Def (ZF_of_word r))
  | _  => None
  end.

(* --------------------------------------------------------------------- *)
Definition all_undef := fun rf =>
  match rf with
  | SF | ZF | PF | OF | CF => Some Undef
  | DF => None
  end.

(* -------------------------------------------------------------------- *)
Implicit Types (ct : condt) (s : x86_mem) (o : oprd) (ir : ireg).
Implicit Types (lbl : label).

(* -------------------------------------------------------------------- *)
Definition check_size_8_64 sz : result error unit:= 
  match sz with
  | U8 | U16 | U32 | U64 => ok tt
  | U128 | U256 => type_error
  end.

Definition check_size_16_64 sz : result error unit:= 
  match sz with
  | U16 | U32 | U64 => ok tt
  | U8 | U128 | U256 => type_error
  end.

Definition check_size_32_64 sz : result error unit:= 
  match sz with
  | U32 | U64 => ok tt
  | U8 | U16 | U128 | U256 => type_error
  end.

(* -------------------------------------------------------------------- *)
Definition eval_MOV sz o1 o2 s : x86_result :=
  Let _ := check_size_8_64 sz in
  Let v := read_oprd sz o2 s in
  write_oprd o1 v s. 

(* -------------------------------------------------------------------- *)
Definition eval_CMOVcc sz ct o1 o2 s : x86_result :=
  Let _ := check_size_16_64 sz in
  Let b := eval_cond ct s.(xrf) in
  if b then eval_MOV sz o1 o2 s else ok s.

(* -------------------------------------------------------------------- *)
Definition eval_ADD sz o1 o2 s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v1 := read_oprd sz o1 s in
  Let v2 := read_oprd sz o2 s in
  let v  := (v1 + v2)%R in
  let vu := (wunsigned v1 + wunsigned v2)%Z in
  let vs := (wsigned   v1 + wsigned   v2)%Z in
  let s  := mem_update_rflags (rflags_of_aluop v vu vs) s in
  write_oprd o1 v s.

(* -------------------------------------------------------------------- *)
Definition eval_SUB sz o1 o2 s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v1 := read_oprd sz o1 s in
  Let v2 := read_oprd sz o2 s in
  let v  := (v1 - v2)%R in
  let vu := (wunsigned v1 - wunsigned v2)%Z in
  let vs := (wsigned   v1 - wsigned   v2)%Z in
  let s  := mem_update_rflags (rflags_of_aluop v vu vs) s in
  write_oprd o1 v s.

(* -------------------------------------------------------------------- *)
(* WARNING: We do not take into account the 8 bits *)
Definition eval_MUL sz o s : x86_result :=
  Let _  := check_size_16_64 sz in
  let v1 := zero_extend sz (s.(xreg) RAX) in
  Let v2 := read_oprd sz o s in
  let lo := (v1 * v2)%R in
  let hi := wmulhu v1 v2 in
  let ov := wdwordu hi lo in
  let ov := (ov >? wmax_unsigned sz)%Z in
  let s  := mem_update_rflags (rflags_of_mul ov) s in
  let s  := mem_write_reg RDX hi s in
  let s  := mem_write_reg RAX lo s in
  ok s.

(* -------------------------------------------------------------------- *)
(* WARNING: We do not take into account the 8 bits *)
Definition eval_IMUL sz o1 (o2 : option (oprd * option u32)) s : x86_result :=
  Let _  := check_size_16_64 sz in
  match o2 with
  | None =>
      let v1 := zero_extend sz (s.(xreg) RAX) in
      Let v2 := read_oprd sz o1 s in
      let lo := (v1 * v2)%R in
      let hi := wmulhs v1 v2 in
      let z  := (wsigned v1 * wsigned v2)%Z in
      let ov := wsigned lo == z in
      let s  := mem_update_rflags (rflags_of_mul ov) s in
      let s  := mem_write_reg RDX hi s in
      let s  := mem_write_reg RAX lo s in
      ok s

  | Some (o2, None) =>
      Let v1 := read_oprd sz o1 s in
      Let v2 := read_oprd sz o2 s in
      let lo := (v1 * v2)%R in
      let z  := (wsigned v1 * wsigned v2)%Z in
      let ov := wsigned lo == z in
      let s  := mem_update_rflags (rflags_of_mul ov) s in
      write_oprd o1 lo s

   | Some (o2, Some v2) =>
      Let v1 := read_oprd sz o2 s in
      let lo := (v1 * zero_extend sz v2)%R in
      let z  := (wsigned v1 * wsigned v2)%Z in
      let ov := wsigned lo == z in
      let s  := mem_update_rflags (rflags_of_mul ov) s in
      write_oprd o1 lo s
  end.

(* -------------------------------------------------------------------- *)
(* WARNING: We do not take into account the 8 bits *)
Definition eval_DIV sz o s : x86_result :=
  Let _  := check_size_16_64 sz in
  let hi := zero_extend sz (s.(xreg) RDX) in
  let lo := zero_extend sz (s.(xreg) RAX) in
  let dd := wdwordu hi lo in
  Let dv := read_oprd sz o s in
  let dv := wunsigned dv in
  let q  := (dd  /  dv)%Z in
  let r  := (dd mod dv)%Z in
  let ov := (q >? wmax_unsigned sz)%Z in

  if (dv == 0)%Z || ov then type_error else

  let s := mem_write_reg RAX (wrepr sz q) s in
  let s := mem_write_reg RDX (wrepr sz r) s in

  ok (mem_update_rflags rflags_of_div s).

(* -------------------------------------------------------------------- *)
(* WARNING: We do not take into account the 8 bits *)
Definition eval_IDIV sz o s : x86_result :=
  Let _  := check_size_16_64 sz in
  let hi := zero_extend sz (s.(xreg) RDX) in
  let lo := zero_extend sz (s.(xreg) RAX) in
  let dd := wdwords hi lo in
  Let dv := read_oprd sz o s in
  let dv := wsigned dv in
  let q  := (Z.quot dd dv)%Z in
  let r  := (Z.rem  dd dv)%Z in
  let ov := (q <? wmin_signed sz)%Z || (q >? wmax_signed sz)%Z in

  if (dv == 0)%Z || ov then type_error else

  let s := mem_write_reg RAX (wrepr sz q) s in
  let s := mem_write_reg RDX (wrepr sz r) s in

  ok (mem_update_rflags rflags_of_div s).

(* -------------------------------------------------------------------- *)
Definition eval_ADC sz o1 o2 s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v1 := read_oprd sz o1 s in
  Let v2 := read_oprd sz o2 s in
  Let c  := st_get_rflag CF s in
  let c  := if c then 1%R else 0%R in
  let v  := (v1 + v2 + c)%R in
  let vu := (wunsigned v1 + wunsigned v2 + wunsigned c)%Z in
  let vs := (wsigned   v1 + wsigned   v2 + wunsigned c)%Z in
  let s  := mem_update_rflags (rflags_of_aluop v vu vs) s in
  write_oprd o1 v s.

(* -------------------------------------------------------------------- *)
Definition eval_SBB sz o1 o2 s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v1 := read_oprd sz o1 s in
  Let v2 := read_oprd sz o2 s in
  Let c  := st_get_rflag CF s in
  let c  := if c then 1%R else 0%R in
  let v  := (v1 - v2 - c)%R in
  let vu := (wunsigned v1 - (wunsigned v2 + wunsigned c))%Z in
  let vs := (wsigned   v1 - (wsigned   v2 + wunsigned c))%Z in
  let s  := mem_update_rflags (rflags_of_aluop v vu vs) s in
  write_oprd o1 v s.

(* -------------------------------------------------------------------- *)
Definition eval_NEG sz o s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let w  := read_oprd sz o s in
  let v  := (- w)%R in
  let vs := (- wsigned w)%Z in
  let s  :=
      mem_update_rflags (
          fun rf =>
          match rf with
          | CF => Some (Def (negb (w == 0%R)))
          | _ => rflags_of_aluop_nocf v vs rf
          end) s
  in write_oprd o v s.

(* -------------------------------------------------------------------- *)
Definition eval_INC sz o s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let w  := read_oprd sz o s in
  let v  := (w + 1)%R in
  let vs := (wsigned w + 1)%Z in
  let s  := mem_update_rflags (rflags_of_aluop_nocf v vs) s in
  write_oprd o v s.

(* -------------------------------------------------------------------- *)
Definition eval_DEC sz o s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let w  := read_oprd sz o s in
  let v  := (w - 1)%R in
  let vs := (wsigned w - 1)%Z in
  let s  := mem_update_rflags (rflags_of_aluop_nocf v vs) s in
  write_oprd o v s.

(* -------------------------------------------------------------------- *)
Definition eval_SETcc ct o s : x86_result :=
  Let b := eval_cond ct s.(xrf) in
  @write_oprd o U8 (if b then 1%R else 0%R) s.

(* -------------------------------------------------------------------- *)
Definition eval_BT sz o ir s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v1 := read_oprd sz o s in
  let v2 := read_ireg sz ir s in
  let b  := wbit v1 v2 in
  ok (mem_set_rflags CF b s).

(* -------------------------------------------------------------------- *)
Definition eval_LEA sz r o2 s : x86_result :=
  Let _  := check_size_32_64 sz in
  Let addr :=
    match o2 with
    | Imm_op w => ok w
    | Adr_op a => ok (decode_addr s a)
    | _        => type_error
    end in
  ok (mem_write_reg r (zero_extend sz addr) s).

(* -------------------------------------------------------------------- *)
Definition eval_TEST sz o1 o2 s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v1 := read_oprd sz o1 s in
  Let v2 := read_oprd sz o2 s in
  let v  := wand v1 v2 in
  ok (mem_update_rflags (rflags_of_bwop v) s).

(* -------------------------------------------------------------------- *)
Definition eval_CMP sz o1 o2 s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v1 := read_oprd sz o1 s in
  Let v2 := read_oprd sz o2 s in
  let v  := (v1 - v2)%R in
  let vu := (wunsigned v1 - wunsigned v2)%Z in
  let vs := (wsigned   v1 - wsigned   v2)%Z in
  ok (mem_update_rflags (rflags_of_aluop v vu vs) s).

(* -------------------------------------------------------------------- *)
Definition eval_AND sz o1 o2 s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v1 := read_oprd sz o1 s in
  Let v2 := read_oprd sz o2 s in
  let v  := wand v1 v2 in
  let s  := mem_update_rflags (rflags_of_bwop v) s in
  write_oprd o1 v s.

(* -------------------------------------------------------------------- *)
Definition eval_OR sz o1 o2 s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v1 := read_oprd sz o1 s in
  Let v2 := read_oprd sz o2 s in
  let v  := wor v1 v2 in
  let s  := mem_update_rflags (rflags_of_bwop v) s in
  write_oprd o1 v s.

(* -------------------------------------------------------------------- *)
Definition eval_XOR sz o1 o2 s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v1 := read_oprd sz o1 s in
  Let v2 := read_oprd sz o2 s in
  let v  := wxor v1 v2 in
  let s  := mem_update_rflags (rflags_of_bwop v) s in
  write_oprd o1 v s.

(* -------------------------------------------------------------------- *)
Definition eval_NOT sz o s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v := read_oprd sz o s in 
  write_oprd o (wnot v) s.

(* -------------------------------------------------------------------- *)
Definition eval_ROR sz o ir s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v := read_oprd sz o s in
  let i := wand (read_ireg U8 ir s) (x86_shift_mask sz) in
  if i == 0%R then ok s else
    let r := wror v (wunsigned i) in
    let cf := msb r in
    let s :=
        if i == 1%R then
          let ro := msb r != msb v in 
          mem_set_rflags OF ro s
        else mem_unset_rflags OF s
    in
    let s := mem_set_rflags CF cf s in
    write_oprd o r s.

(* -------------------------------------------------------------------- *)
Definition eval_ROL sz o ir s : x86_result :=
  Let _  := check_size_8_64 sz in
  Let v := read_oprd sz o s in
  let i := wand (read_ireg U8 ir s) (x86_shift_mask sz) in
  if i == 0%R then ok s else
    let r := wrol v (wunsigned i) in 
    let cf := lsb r in
    let s :=
        if i == 1%R then
          let ro := msb r != cf in
          mem_set_rflags OF ro s
        else mem_unset_rflags OF s
    in
    let s := mem_set_rflags CF cf s in
    write_oprd o r s.

(* -------------------------------------------------------------------- *)
Definition eval_SHL sz o ir s : x86_result :=
  Let _ := check_size_8_64 sz in
  Let v := read_oprd sz o s in
  let i := wand (read_ireg U8 ir s) (x86_shift_mask sz) in

  if i == 0%R then ok (mem_update_rflags all_undef s) (* FIXME preserve the flags *)
  else
    let rc := msb (wshl v (wunsigned i - 1)) in
    let r  := wshl v (wunsigned i) in
    let s  := mem_update_rflags (rflags_of_sh i (msb r (+) rc) r rc) s in
    write_oprd o r s.

(* -------------------------------------------------------------------- *)
Definition eval_SHLD sz o1 r2 ir s : x86_result :=
  Let _  := check_size_16_64 sz in
  Let v1 := read_oprd sz o1 s in
  let v2 := zero_extend sz (s.(xreg) r2) in 
  let i := wand (read_ireg U8 ir s) (x86_shift_mask sz) in (* FIXME: enforce ir is CL or immediate *)

  if i == 0%R then ok (mem_update_rflags all_undef s) (* FIXME preserve the flags *)
  else
    let rc := msb (wshl v1 (wunsigned i - 1)) in
    let r1 := wshl v1 (wunsigned i) in
    let r2 := wshr v2 (wsize_bits sz - wunsigned i) in
    let r  := wor r1 r2 in
    let s  := mem_update_rflags (rflags_of_sh i (msb r (+) rc) r rc) s in
    write_oprd o1 r s.

(* -------------------------------------------------------------------- *)
Definition eval_SHR sz o ir s : x86_result :=
  Let _ := check_size_8_64 sz in
  Let v := read_oprd sz o s in
  let i := wand (read_ireg U8 ir s) (x86_shift_mask sz) in

  if i == 0%R then ok (mem_update_rflags all_undef s) (* FIXME preserve the flags *)
  else 
    let rc := lsb (wshr v (wunsigned i - 1)) in
    let r  := wshr v (wunsigned i) in
    let s  := mem_update_rflags (rflags_of_sh i (msb r) r rc) s in
    write_oprd o r s.

(* -------------------------------------------------------------------- *)
Definition eval_SAL sz o ir s : x86_result :=
  eval_SHL sz o ir s.

(* -------------------------------------------------------------------- *)
Definition eval_SAR sz o ir s : x86_result :=
  Let _ := check_size_8_64 sz in
  Let v := read_oprd sz o s in
  let i := wand (read_ireg U8 ir s) (x86_shift_mask sz) in

  if i == 0%R then ok (mem_update_rflags all_undef s) else
    let rc := lsb (wsar v (wunsigned i - 1)) in
    let r  := wsar v (wunsigned i) in
    let s  := mem_update_rflags (rflags_of_sh i false r rc) s
    in write_oprd o r s.

(* -------------------------------------------------------------------- *)
Definition eval_JMP lbl (s: x86_state) : x86_result_state :=
  Let ip := find_label lbl s.(xc) in ok (st_write_ip ip.+1 s).

(* -------------------------------------------------------------------- *)
Definition eval_Jcc lbl ct (s: x86_state) : x86_result_state :=
  Let b := eval_cond ct s.(xrf) in
  if b then eval_JMP lbl s else ok (st_write_ip (xip s).+1 s).

(* -------------------------------------------------------------------- *)
Definition eval_instr_mem (i : asm) s : x86_result :=
  match i with
  | JMP    _
  | Jcc    _ _
  | LABEL  _           => ok s
  | MOV    sz o1 o2    => eval_MOV    sz o1 o2 s
  | CMOVcc sz ct o1 o2 => eval_CMOVcc sz ct o1 o2 s
  | ADD    sz o1 o2    => eval_ADD    sz o1 o2 s
  | SUB    sz o1 o2    => eval_SUB    sz o1 o2 s
  | MUL    sz o        => eval_MUL    sz o s
  | IMUL   sz o1 o2i   => eval_IMUL   sz o1 o2i s
  | DIV    sz o        => eval_DIV    sz o s
  | IDIV   sz o        => eval_IDIV   sz o s
  | ADC    sz o1 o2    => eval_ADC    sz o1 o2 s
  | SBB    sz o1 o2    => eval_SBB    sz o1 o2 s
  | NEG    sz o        => eval_NEG    sz o s
  | INC    sz o        => eval_INC    sz o s
  | DEC    sz o        => eval_DEC    sz o s
  | SETcc     ct o     => eval_SETcc  ct o s
  | BT     sz o ir     => eval_BT     sz o ir s
  | LEA    sz o1 o2    => eval_LEA    sz o1 o2 s
  | TEST   sz o1 o2    => eval_TEST   sz o1 o2 s
  | CMP    sz o1 o2    => eval_CMP    sz o1 o2 s
  | AND    sz o1 o2    => eval_AND    sz o1 o2 s
  | OR     sz o1 o2    => eval_OR     sz o1 o2 s
  | XOR    sz o1 o2    => eval_XOR    sz o1 o2 s
  | NOT    sz o        => eval_NOT    sz o s
  | ROR    sz o ir     => eval_ROR    sz o ir s
  | ROL    sz o ir     => eval_ROL    sz o ir s
  | SHL    sz o ir     => eval_SHL    sz o ir s
  | SHR    sz o ir     => eval_SHR    sz o ir s
  | SAL    sz o ir     => eval_SAL    sz o ir s
  | SAR    sz o ir     => eval_SAR    sz o ir s
  | SHLD   sz o1 o2 ir => eval_SHLD   sz o1 o2 ir s
  end.

Definition eval_instr (i : asm) (s: x86_state) : x86_result_state :=
  match i with
  | LABEL  _        => ok (st_write_ip (xip s).+1 s)
  | JMP    lbl      => eval_JMP lbl s
  | Jcc    lbl ct   => eval_Jcc lbl ct s
  | _ =>
    Let m := eval_instr_mem i s in
    ok {|
        xm := m;
        xc := s.(xc);
        xip := s.(xip).+1
      |}
  end.

(* -------------------------------------------------------------------- *)
Definition fetch_and_eval (s: x86_state) :=
  if oseq.onth s.(xc) s.(xip) is Some i then
    eval_instr i s
  else type_error.

Definition x86sem1 (s1 s2: x86_state) : Prop :=
  fetch_and_eval s1 = ok s2.

Definition x86sem : relation x86_state := clos_refl_trans x86_state x86sem1.

End GLOB_DEFS.

(* -------------------------------------------------------------------- *)
Record xfundef := XFundef {
 xfd_stk_size : Z;
 xfd_nstk : register;
 xfd_arg  : seq register;
 xfd_body : seq asm;
 xfd_res  : seq register;
}.

Definition xprog : Type :=
  seq (funname * xfundef).

Definition mem_write_regs m rs (vs:seq u64) :=
    foldl (λ m rv, let '(r,v) := rv in mem_write_reg r v m) m (zip rs vs).

Lemma mem_write_regs_cons m r rs v vs :
  mem_write_regs m (r :: rs) (v :: vs) =
  mem_write_regs (mem_write_reg r v m) rs vs.
Proof. by []. Qed.

(* FIXME: initial register map *)
Variant x86sem_fd (P: xprog) (gd: glob_defs) m1 fn va m2 vr : Prop :=
| X86Sem_fd fd mp m2'
   `(get_fundef P fn = Some fd)
   `(alloc_stack m1 fd.(xfd_stk_size) = ok mp)
    (c := fd.(xfd_body))
    (m1' := mem_write_reg fd.(xfd_nstk) (top_stack mp) {| xmem := mp ; xreg := regmap0 ; xrf := rflagmap0 |})
    `(size va = size fd.(xfd_arg))
    (m1'' := mem_write_regs m1' fd.(xfd_arg) va)
    `(x86sem gd {| xm := m1'' ; xc := c ; xip := 0 |} {| xm := m2'; xc := c; xip := size c |})
    `(vr = map (λ r, m2'.(xreg) r) fd.(xfd_res))
    `(m2 = free_stack m2'.(xmem) fd.(xfd_stk_size))
    : x86sem_fd P gd m1 fn va m2 vr.

Definition x86sem_trans gd s2 s1 s3 :
  x86sem gd s1 s2 -> x86sem gd s2 s3 -> x86sem gd s1 s3 :=
  rt_trans _ _ s1 s2 s3.
