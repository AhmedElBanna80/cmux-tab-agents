import { useState } from 'react'

interface TodoFormProps {
  onAdd: (text: string) => void
}

export function TodoForm({ onAdd }: TodoFormProps) {
  const [text, setText] = useState('')

  const trimmed = text.trim()

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!trimmed) return
    onAdd(trimmed)
    setText('')
  }

  return (
    <form onSubmit={handleSubmit}>
      <input
        type="text"
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="New task…"
        aria-label="New task"
      />
      <button type="submit" disabled={!trimmed}>
        Add
      </button>
    </form>
  )
}
