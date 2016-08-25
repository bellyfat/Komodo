DAFNYFLAGS = /noNLarith /timeLimit:60 /trace /rewriteOpaqueUseFuel:0
SPARTANFLAGS = #-assumeUpdates 1

# top-level target
.PHONY: verified
verified: $(dir)/main.S

mkdeps = $(foreach n,$($(notdir $(1))_dep-dfy) $($(notdir $(1))_dep-sdfy),$(dir)/$(n).verified)
mkdfyincs = $(foreach n,$($(notdir $(1))_dep-dfy),-i $(2)$(n).dfy)
mksdfyincs = $(foreach n,$($(notdir $(1))_dep-sdfy),-i $(2)$(n).gen.dfy -include $(dir)/$(n).sdfy)
mkincs-dir = $(call mkdfyincs,$(1),$(dir)/) $(call mksdfyincs,$(1),$(dir)/)
mkincs-nodir = $(call mkdfyincs,$(1),) $(call mksdfyincs,$(1),)

# We use .verified files as a timestamp/placeholder to indicate that
# a given source has been verified.

# Spartan-to-Dafny
# NB: Spartan include paths are relative to the (generated) dfy file, not the CWD
%.gen.dfy: %.sdfy
	$(SPARTAN) $(SPARTANFLAGS) $(call mkincs-nodir,$*) $< -out $@
	@which dos2unix >/dev/null && dos2unix $@ || true

# Spartan direct verification, including cheesy workaround for broken error code.
%.verified %.log: %.sdfy %.gen.dfy
	/bin/bash -c "$(SPARTAN) $(SPARTANFLAGS) $(call mkincs-dir,$*) $< \
	-dafnyDirect $(DAFNYFLAGS) /compile:0 | tee $*.log; exit \$${PIPESTATUS[0]}"
	@grep -q "^Dafny program verifier finished with [^0][0-9]* verified, 0 errors$$" $*.log && touch $*.verified
	@$(RM) $*.log

%.verified: %.dfy
	$(DAFNY) $(DAFNYFLAGS) /compile:0 $< && touch $@

%.exe: %.i.dfy %.i.verified
	$(DAFNY) $(DAFNYFLAGS) /noVerify /compile:2 /out:$@ $<

%.S: %.exe
	$< > $@

# temp target to produce a bootable image
$(dir)/%.img: $(dir)/%.o
	$(OBJCOPY) $< -O binary $@

CLEAN := $(CLEAN) $(dir)/*.exe $(dir)/*.dll $(dir)/*.pdb $(dir)/*.S $(dir)/*.o $(dir)/*.verified $(dir)/*.gen.dfy

# keep all "intermediate" files around, to avoid pointless re-verification
.SECONDARY:

# delete output files if the command failed
.DELETE_ON_ERROR:

# deps for all Dafny code
$(dir)/ARMdef.verified: $(dir)/assembly.s.verified $(dir)/Maybe.verified $(dir)/Seq.verified
$(dir)/ARMprint.verified: $(dir)/ARMdef.verified
$(dir)/ARMspartan.verified: $(dir)/ARMdef.verified
$(dir)/kev_common.s.verified: $(dir)/ARMdef.verified
$(dir)/pagedb.s.verified: $(dir)/kev_common.s.verified $(dir)/Maybe.verified $(dir)/Sets.verified
$(dir)/kev_common.i.verified: $(dir)/ARMspartan.verified $(dir)/kev_common.s.verified $(dir)/pagedb.s.verified
$(dir)/smcapi.s.verified: $(dir)/kev_common.s.verified $(dir)/pagedb.s.verified
$(dir)/smcapi.i.verified: $(dir)/smcapi.s.verified
$(dir)/pagedb.i.verified: $(dir)/pagedb.s.verified $(dir)/kev_common.i.verified
$(dir)/entry.s.verified:  $(dir)/kev_common.s.verified $(dir)/ARMdef.verified $(dir)/pagedb.s.verified $(dir)/smcapi.s.verified $(dir)/abstate.s.verified
$(dir)/entry.i.verified: $(dir)/entry.s.verified
$(dir)/main.i.verified: $(dir)/ARMprint.verified $(dir)/smc_handler.verified

# variables used to emit deps/includes for all Spartan code
ARMdecls_dep-dfy = ARMspartan
$(dir)/ARMdecls.verified: $(call mkdeps,ARMdecls)

kev_utils_dep-sdfy = ARMdecls
kev_utils_dep-dfy = ARMspartan kev_common.i
$(dir)/kev_utils.verified: $(call mkdeps,kev_utils)

allocate_page_dep-sdfy = ARMdecls kev_utils
allocate_page_dep-dfy = ARMspartan Sets kev_common.i pagedb.i smcapi.i
$(dir)/allocate_page.verified: $(call mkdeps,allocate_page)

init_addrspace_dep-sdfy = ARMdecls kev_utils
init_addrspace_dep-dfy = ARMspartan kev_common.i pagedb.i smcapi.i
$(dir)/init_addrspace.verified: $(call mkdeps,init_addrspace)

init_dispatcher_dep-sdfy = ARMdecls kev_utils allocate_page
init_dispatcher_dep-dfy = ARMspartan kev_common.i pagedb.i smcapi.i
$(dir)/init_dispatcher.verified: $(call mkdeps,init_dispatcher)

init_l2ptable_dep-sdfy = ARMdecls kev_utils allocate_page
init_l2ptable_dep-dfy = ARMspartan kev_common.i pagedb.i smcapi.i
$(dir)/init_l2ptable.verified: $(call mkdeps,init_l2ptable)

enter_resume_dep-sdfy = ARMdecls kev_utils
enter_resume_dep-dfy = ARMspartan kev_common.i pagedb.i smcapi.i abstate.s entry.i
$(dir)/enter_resume.verified: $(call mkdeps,enter_resume)

smc_handler_dep-sdfy = ARMdecls kev_utils init_addrspace init_dispatcher \
    init_l2ptable enter_resume
smc_handler_dep-dfy = ARMspartan kev_common.i pagedb.i smcapi.i
$(dir)/smc_handler.verified: $(call mkdeps,smc_handler)
