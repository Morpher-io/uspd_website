export async function GET(
  _request: NextRequest,
  context: { params: { id: string } }
) {
  const { params } = context;
  const tokenId = params.id;
  // ... the rest of the function
}
