/**
 * Parses the TICKETS environment variable into an array of ticket Object IDs.
 * @param minCount Minimum number of tickets required (default: 1)
 * @returns Array of ticket Object IDs
 */
export function parseTicketIds(minCount: number = 1): string[] {
  const ticketsEnv = process.env.TICKETS;
  if (!ticketsEnv) {
    throw new Error("TICKETS environment variable is required.");
  }

  const ticketIds = ticketsEnv
    .split(",")
    .map((id) => id.trim())
    .filter((id) => id.length > 0);

  // Check for duplicates
  const uniqueTicketIds = new Set(ticketIds);
  if (uniqueTicketIds.size !== ticketIds.length) {
    const duplicates = ticketIds.filter((item, index) => ticketIds.indexOf(item) !== index);
    const uniqueDuplicates = Array.from(new Set(duplicates));
    throw new Error(`Duplicate ticket IDs found: ${uniqueDuplicates.join(", ")}`);
  }

  if (ticketIds.length < minCount) {
    throw new Error(`Not enough tickets provided! Found ${ticketIds.length} but need at least ${minCount}.`);
  }

  console.log("\nParsed Ticket IDs:");
  ticketIds.forEach((id, index) => {
    console.log(`  ${(index + 1).toString().padStart(2, " ")}. ${id}`);
  });

  return ticketIds;
}
