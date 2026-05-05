import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, it, expect, vi } from 'vitest'
import { TodoForm } from '../TodoForm'

describe('TodoForm', () => {
  it('renders an input field and an Add button', () => {
    render(<TodoForm onAdd={vi.fn()} />)
    expect(screen.getByRole('textbox')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /add/i })).toBeInTheDocument()
  })

  it('calls onAdd with the trimmed text and clears the input', async () => {
    const user = userEvent.setup()
    const onAdd = vi.fn()
    render(<TodoForm onAdd={onAdd} />)

    await user.type(screen.getByRole('textbox'), 'Buy groceries')
    await user.click(screen.getByRole('button', { name: /add/i }))

    expect(onAdd).toHaveBeenCalledOnce()
    expect(onAdd).toHaveBeenCalledWith('Buy groceries')
    expect(screen.getByRole('textbox')).toHaveValue('')
  })

  it('disables the Add button when the input is empty', () => {
    render(<TodoForm onAdd={vi.fn()} />)
    expect(screen.getByRole('button', { name: /add/i })).toBeDisabled()
  })

  it('disables the Add button when the input is only whitespace', async () => {
    const user = userEvent.setup()
    render(<TodoForm onAdd={vi.fn()} />)

    await user.type(screen.getByRole('textbox'), '   ')
    expect(screen.getByRole('button', { name: /add/i })).toBeDisabled()
  })
})
