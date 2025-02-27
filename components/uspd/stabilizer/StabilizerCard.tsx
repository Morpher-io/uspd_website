import { Card, CardContent, CardHeader, CardTitle, CardFooter } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import Link from 'next/link'

interface StabilizerCardProps {
  balance: number | undefined
  hasMinterRole?: boolean
  isLoading: boolean
}

export function StabilizerCard({ balance, hasMinterRole, isLoading }: StabilizerCardProps) {
  if (isLoading) {
    return <p>Loading...</p>
  }

  if (!balance || balance === 0) {
    return (
      <Alert>
        <AlertDescription className='text-center'>
          You don't have any Stabilizer NFTs
        </AlertDescription>
      </Alert>
    )
  }

  return (
    <div className="flex flex-col gap-6 w-full items-center">
      <Card className="w-[400px]">
        <CardHeader>
          <CardTitle>Your Stabilizer NFTs</CardTitle>
        </CardHeader>
        <CardContent>
          <p>You have {balance} Stabilizer NFT(s)</p>
        </CardContent>
      </Card>

      {hasMinterRole && (
        <Card className="w-[400px] mt-6">
          <CardHeader>
            <CardTitle>Stabilizer Admin</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="mb-4">You have admin privileges to mint new Stabilizer NFTs.</p>
          </CardContent>
          <CardFooter>
            <Link href="/stabilizer/mint" className="w-full">
              <Button className="w-full">Go to Minting Page</Button>
            </Link>
          </CardFooter>
        </Card>
      )}
    </div>
  )
}
