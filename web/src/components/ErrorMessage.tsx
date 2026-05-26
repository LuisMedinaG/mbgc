interface Props {
  message: string
}

export default function ErrorMessage({ message }: Props) {
  return (
    <div className="text-center py-8 px-4 text-danger">
      {message}
    </div>
  )
}