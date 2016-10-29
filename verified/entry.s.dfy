include "kom_common.s.dfy"
include "ARMdef.dfy"
include "pagedb.s.dfy"
include "smcapi.s.dfy"
include "abstate.s.dfy"

predicate nonStoppedL1(d:PageDb, l1:PageNr)
{
    validL1PTPage(d, l1) && !hasStoppedAddrspace(d, l1)
}

predicate nonStoppedDispatcher(d:PageDb, p:PageNr)
{
    validDispatcherPage(d,p) && (validPageDbImpliesWellFormed(d);
        !hasStoppedAddrspace(d,p))
}

function l1pOfDispatcher(d:PageDb, p:PageNr) : PageNr
    requires validDispatcherPage(d, p) && !hasStoppedAddrspace(d, p)
    ensures  nonStoppedL1(d,l1pOfDispatcher(d,p))
{
    reveal_validPageDb();
    d[d[p].addrspace].entry.l1ptnr
}


// This must hold between all consecutive states on the addsrpace entry/return path.
predicate validERTransition(s:SysState, s':SysState, dispPg:PageNr)
    requires validDispatcherPage(s.d, dispPg)
{
    reveal_validPageDb();
    validSysState(s) && validSysState(s') &&
    (validERTransitionHW(s.hw, s'.hw, s.d)
    && equivalentExceptPage(s.d, s'.d, dispPg)
    && nonStoppedDispatcher(s.d, dispPg) && nonStoppedDispatcher(s'.d, dispPg)
    && page_paddr(l1pOfDispatcher(s.d, dispPg))  == s.hw.conf.ttbr0.ptbase
    && s.hw.conf.ttbr0.ptbase == s'.hw.conf.ttbr0.ptbase
    && WSMemInvariantExceptAddrspaceAtPage(s.hw, s'.hw, s.d,
        l1pOfDispatcher(s.d, dispPg)))
}

function securePageFromPhysAddr(phys:int): PageNr
    requires PageAligned(phys)
    requires SecurePhysBase() <= phys < SecurePhysBase() +
        KOM_SECURE_NPAGES() * PAGESIZE() // physPageIsSecure(phys/PAGESIZE())
    ensures validPageNr(securePageFromPhysAddr(phys))
{
    (phys - SecurePhysBase()) / PAGESIZE()
}

predicate validERTransitionHW(hw:state, hw':state, d:PageDb)
{
    reveal_validPageDb();
    reveal_ValidConfig();
    ValidState(hw) && ValidState(hw') && hw'.conf.ttbr0 == hw.conf.ttbr0
    && physPageIsSecure(hw.conf.ttbr0.ptbase / PAGESIZE())
    && nonStoppedL1(d, securePageFromPhysAddr(hw.conf.ttbr0.ptbase))
    //&& bankedRegsPreserved(hw, hw')
}

predicate validSysStates(sset:set<SysState>) { forall s :: s in sset ==> validSysState(s) }

// This is just here to make verification easier. It allows irrelevant state 
// (i.e. some regs) to be changed while checking for error conditions.
predicate errCheck(s:SysState, s':SysState)
{
   validSysState(s) && validSysState(s') && s.d == s'.d
}

predicate validEnter(s:SysState,s':SysState,
    dispPage:word,a1:word,a2:word,a3:word)
    requires validSysState(s)
    // requires smc_enter(s.d, dispPage, a1, a2, a3).1 == KOM_ERR_SUCCESS()
{
    reveal_ValidRegState();
    reveal_validExceptionTransition();
    smc_enter(s.d, dispPage, a1, a2, a3).1 != KOM_ERR_SUCCESS() ||
   
    ((exists serr, s2, s3, s4 :: validSysStates({serr,s2,s3,s4})
        && errCheck(s, serr)
        && preEntryEnter(serr,s2,dispPage,a1,a2,a3)
        && entryTransitionEnter(s2, s3, dispPage)
        && s4.d == s3.d && userspaceExecution(s3.hw, s4.hw, s3.d)
        && mode_of_state(s4.hw) != User
        && validExceptionTransition(s4, s', dispPage)
        && (s'.hw.regs[R0], s'.hw.regs[R1], s'.d)==
            exceptionHandled(s4, dispPage))
    && bankedRegsPreserved(s.hw, s'.hw))
}

predicate validResume(s:SysState,s':SysState,dispPg:word)
    requires validSysState(s)
{
     
    reveal_ValidRegState();
    reveal_validExceptionTransition();
    smc_resume(s.d, dispPg).1 != KOM_ERR_SUCCESS() ||
   
    ((exists serr, s2, s3, s4 :: validSysStates({serr,s2,s3,s4})
        && errCheck(s, serr)
        && preEntryResume(serr,s2,dispPg)
        && entryTransitionResume(s2, s3, dispPg)
        && s4.d == s3.d && userspaceExecution(s3.hw, s4.hw, s3.d)
        && mode_of_state(s4.hw) != User
        && validExceptionTransition(s4, s', dispPg)
        && (s'.hw.regs[R0], s'.hw.regs[R1], s'.d)==
            exceptionHandled(s4, dispPg))
    && bankedRegsPreserved(s.hw, s'.hw))
}

predicate preEntryEnter(s:SysState,s':SysState,
    dispPage:PageNr,a1:word,a2:word,a3:word)
    requires validSysState(s)
    requires smc_enter(s.d, dispPage, a1, a2, a3).1 == KOM_ERR_SUCCESS()
    ensures preEntryEnter(s,s',dispPage,a1,a2,a3) ==>
        PageAligned(s'.hw.conf.ttbr0.ptbase) &&
        SecurePhysBase() <= s'.hw.conf.ttbr0.ptbase < SecurePhysBase() +
            KOM_SECURE_NPAGES() * PAGESIZE()
    ensures preEntryEnter(s,s',dispPage,a1,a2,a3) ==>
        nonStoppedL1(s'.d, securePageFromPhysAddr(s'.hw.conf.ttbr0.ptbase));
{
    reveal_validPageDb();
    reveal_ValidRegState();
    var addrspace := s.d[s.d[dispPage].addrspace];
    assert isAddrspace(s.d, s.d[dispPage].addrspace);
    var l1p := addrspace.entry.l1ptnr; // l1pOfDispatcher(s.d, dispPage);
    assert s.d[l1p].addrspace == s.d[dispPage].addrspace;
    assert addrspace.entry.state == FinalState;
    assert !hasStoppedAddrspace(s.d, l1p);

    validSysState(s') &&  s.d == s'.d &&
    s'.hw.conf.ttbr0.ptbase == page_paddr(l1p) &&
    s'.hw.conf.scr.ns == Secure &&
    s'.hw.regs[R0] == a1 && s'.hw.regs[R1] == a2 && s'.hw.regs[R2] == a3 &&

    WSMemInvariantExceptAddrspaceAtPage(s.hw, s'.hw, s.d, l1p)
}

predicate preEntryResume(s:SysState, s':SysState, dispPage:PageNr)
    requires validSysState(s)
    requires smc_resume(s.d, dispPage).1 == KOM_ERR_SUCCESS()
    ensures preEntryResume(s,s',dispPage) ==>
        PageAligned(s'.hw.conf.ttbr0.ptbase) &&
        SecurePhysBase() <= s'.hw.conf.ttbr0.ptbase < SecurePhysBase() +
            KOM_SECURE_NPAGES() * PAGESIZE()
    ensures preEntryResume(s,s',dispPage) ==>
        nonStoppedL1(s'.d, securePageFromPhysAddr(s'.hw.conf.ttbr0.ptbase));
{
    reveal_validPageDb();
    var disp := s.d[dispPage].entry;
    var l1p := l1pOfDispatcher(s.d, dispPage);
    
    validSysState(s') && s'.d == s.d &&
    s'.hw.conf.ttbr0.ptbase == page_paddr(l1p) && //l1pOfDispatcher(s.d, dispPage) &&
    s'.hw.conf.scr.ns == Secure &&

    (reveal_ValidRegState(); 
    s'.hw.regs[R0] == disp.ctxt.regs[R0] &&
    s'.hw.regs[R1] == disp.ctxt.regs[R1] &&
    s'.hw.regs[R2] == disp.ctxt.regs[R2] &&
    s'.hw.regs[R3] == disp.ctxt.regs[R3] &&
    s'.hw.regs[R4] == disp.ctxt.regs[R4] &&
    s'.hw.regs[R5] == disp.ctxt.regs[R5] &&
    s'.hw.regs[R6] == disp.ctxt.regs[R6] &&
    s'.hw.regs[R7] == disp.ctxt.regs[R7] &&
    s'.hw.regs[R8] == disp.ctxt.regs[R8] &&
    s'.hw.regs[R9] == disp.ctxt.regs[R9] &&
    s'.hw.regs[R10] == disp.ctxt.regs[R10] &&
    s'.hw.regs[R11] == disp.ctxt.regs[R11] &&
    s'.hw.regs[R12] == disp.ctxt.regs[R12] &&
    s'.hw.regs[LR(User)] == disp.ctxt.regs[LR(User)] &&
    s'.hw.regs[SP(User)] == disp.ctxt.regs[SP(User)]) &&
    
    (reveal_ValidSRegState();
    s'.hw.sregs[spsr(Monitor)] == disp.ctxt.cpsr) &&
    //s'.hw.conf.cpsr == decode_psr(disp.ctxt.cpsr)) &&
    
    WSMemInvariantExceptAddrspaceAtPage(s.hw, s'.hw, s.d, l1p)

}

predicate entryTransitionEnter(s:SysState, s':SysState, dispPg:PageNr)
    requires validDispatcherPage(s.d, dispPg)
    ensures entryTransitionEnter(s, s', dispPg) ==> mode_of_state(s'.hw) == User
{
    validERTransition(s, s', dispPg) && s'.d == s.d
    && evalEnterUserspace(s.hw, s'.hw)
    && s'.hw.steps == s.hw.steps + 1
    && OperandContents(s.hw, OLR) == s.d[dispPg].entry.entrypoint
}

predicate entryTransitionResume(s:SysState, s':SysState, dispPg:PageNr)
    requires validDispatcherPage(s.d, dispPg)
{
    validSysState(s) && validSysState(s') && s.d == s'.d
    && evalEnterUserspace(s.hw, s'.hw)
    && s'.hw.steps == s.hw.steps + 1
    && (var disp := s.d[dispPg].entry;
    OperandContents(s.hw, OLR) == disp.ctxt.pc)
}

predicate userspaceExecution(hw:state, hw':state, d:PageDb)
    requires ValidState(hw) && mode_of_state(hw) == User
    ensures userspaceExecution(hw, hw', d) ==> mode_of_state(hw') != User
{
    validERTransitionHW(hw, hw', d)
    && exists s, ex :: evalUserspaceExecution(hw, s)
    && evalExceptionTaken(s, ex, hw')
    // frownyface about this assert -> :(
    && WSMemInvariantExceptAddrspace(hw, hw', d)
    && hw.conf.excount + 1 == hw'.conf.excount
    && hw'.conf.exstep == hw'.steps
    && mode_of_state(hw') != User
}

//-----------------------------------------------------------------------------
// Exception Handler Spec
//-----------------------------------------------------------------------------
function exceptionHandled(s:SysState, dispPg:PageNr) : (word, word, PageDb)
    requires validSysState(s)
    requires mode_of_state(s.hw) != User
    requires validDispatcherPage(s.d, dispPg)
    // This should be true since the exception is taken from user mode
    requires 
        (reveal_ValidSRegState();
        decode_mode'(psr_mask_mode(
        s.hw.sregs[spsr(mode_of_state(s.hw))])) == Just(User))
    ensures var (r0,r1,d') := exceptionHandled(s, dispPg);
        wellFormedPageDb(d')
{
    reveal_validPageDb();
    reveal_ValidSRegState();
    reveal_ValidRegState();
    if(s.hw.conf.ex.ExSVC?) then
        var p := dispPg;
        var d' := s.d[ p := s.d[p].(entry := s.d[p].entry.(entered := false))];
        (KOM_ERR_SUCCESS(), s.hw.regs[R0], d')
    else 
        var p := dispPg;
        var pc := OperandContents(s.hw, OLR);
        var psr := s.hw.sregs[spsr(mode_of_state(s.hw))];
        assert decode_mode'(psr_mask_mode(psr)) == Just(User);
        var ctxt' := DispatcherContext(s.hw.regs, pc, psr);
        assert decode_mode'(psr_mask_mode(ctxt'.cpsr)) == Just(User);
        assert validDispatcherContext(ctxt');
        var disp' := s.d[p].entry.(entered:=true, ctxt:=ctxt');
        var d' := s.d[ p := s.d[p].(entry := disp') ];
        assert wellFormedPageDbEntry(s.d[p].(entry := disp'));
        assert wellFormedPageDb(d');
        if s.hw.conf.ex.ExIRQ? || s.hw.conf.ex.ExFIQ? then
            (KOM_ERR_INTERRUPTED(), 0, d')
        else
            assert s.hw.conf.ex.ExAbt? || s.hw.conf.ex.ExUnd? ||
                s.hw.conf.ex.ExUnd?;
            (KOM_ERR_FAULT(), 0, d')
}

predicate {:opaque} validExceptionTransition(s:SysState, s':SysState, dispPg: PageNr)
    requires validDispatcherPage(s.d, dispPg)
    ensures validExceptionTransition(s,s',dispPg) ==>
        validSysState(s) && validSysState(s')
{
    reveal_validPageDb();
    reveal_ValidRegState();
    reveal_ValidMemState();
    validSysState(s) && validSysState(s') &&
    (validERTransitionHW(s.hw, s'.hw, s.d)
    && equivalentExceptPage(s.d, s'.d, dispPg) 
    && nonStoppedDispatcher(s.d, dispPg) && nonStoppedDispatcher(s'.d, dispPg)
    && page_paddr(l1pOfDispatcher(s.d, dispPg)) == s.hw.conf.ttbr0.ptbase
    && s.hw.conf.ttbr0.ptbase == s'.hw.conf.ttbr0.ptbase  
    // && (forall g | ValidGlobal(g) && g != PageDb() ::
    //    GlobalFullContents(s.hw.m, g) == GlobalFullContents(s'.hw.m, g))
    && (forall p:PageNr | p != dispPg :: s.d[p] == s'.d[p])
        //extractPageDbEntry(s.hw.m, p) == extractPageDbEntry(s'.hw.m, p))
    && (forall a:addr | a in TheValidAddresses() && !(StackLimit() <= a < StackBase()) && 
        !(addrInPage(a, dispPg)) :: s.hw.m.addresses[a] == s'.hw.m.addresses[a])
    && mode_of_state(s.hw) != User 
    && mode_of_state(s'.hw) == Monitor)
}

// All writeable and secure memory addresses except the ones in the active l1
// page table have their contents preserved
predicate WSMemInvariantExceptAddrspace(hw:state, hw':state, d:PageDb)
    // requires validERTransition(s, s')
    // requires userEnteredState(s) && userEnteredState(s')
    requires ValidState(hw)
    requires validERTransitionHW(hw, hw', d)
{
    reveal_ValidConfig();
    WSMemInvariantExceptAddrspaceAtPage(hw, hw', d,
        securePageFromPhysAddr(hw.conf.ttbr0.ptbase))
}

predicate WSMemInvariantExceptAddrspaceAtPage(hw:state, hw':state, 
        d:PageDb, l1p:PageNr)
    requires ValidState(hw) && ValidState(hw') && nonStoppedL1(d, l1p)
{
    forall a | ValidMem(a) && address_is_secure(a) && !memSWrInAddrspace(d, l1p, a) ::
        MemContents(hw.m, a) == MemContents(hw'.m, a)
}


// Is the page secure, writeable, and in the L1PT
predicate pageSWrInAddrspace(d:PageDb, l1p:PageNr, p:PageNr)
    requires validPageNr(p) && validL1PTPage(d, l1p)
    requires (validPageDbImpliesWellFormed(d); !hasStoppedAddrspace(d, l1p))
{
    reveal_validPageDb();
    !hasStoppedAddrspace(d, l1p) && 
    var l1pt := d[l1p].entry.l1pt;
    exists p' :: Just(p') in l1pt && assert validL1PTE(d, p'); pageSWrInL2PT(d[p'].entry.l2pt,p)
}

predicate memSWrInAddrspace(d:PageDb, l1p:PageNr, m: addr)
    requires validL1PTPage(d, l1p)
    requires (validPageDbImpliesWellFormed(d); !hasStoppedAddrspace(d, l1p))
{
    exists p | validPageNr(p) :: pageSWrInAddrspace(d, l1p, p) && addrInPage(m, p)
}

// is the page secure, writeable, and in the L2PT
predicate pageSWrInL2PT(l2pt:seq<L2PTE>, p:PageNr)
{
    exists pte :: pte in l2pt && pte.SecureMapping? && pte.page == p && pte.write
}

predicate equivalentExceptPage(d:PageDb, d':PageDb, p:PageNr)
    requires validPageNr(p)
    requires validPageDb(d) && validPageDb(d')
{
    validPageDbImpliesWellFormed(d);
    validPageDbImpliesWellFormed(d');
    forall p' :: validPageNr(p') && p' != p ==> d[p'] == d'[p']
}
