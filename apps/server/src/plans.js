export function planLimits(user){
  const expanded=user?.plan==='beta'||user?.plan==='unbound';
  return {devices:expanded?10:3,rooms:expanded?10:1,roomMembers:expanded?30:10,advancedAppearance:expanded,animatedProfile:expanded,libraryImport:expanded,discordPresence:expanded};
}
