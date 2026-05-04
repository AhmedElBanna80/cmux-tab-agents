import { useState } from 'react'
import { TodoForm } from './TodoForm'

interface Todo {
  id: number
  text: string
  completed: boolean
}

export function TodoApp() {
  const [todos, setTodos] = useState<Todo[]>([])
  const [nextId, setNextId] = useState(1)

  function handleAdd(text: string) {
    setTodos((prev) => [...prev, { id: nextId, text, completed: false }])
    setNextId((n) => n + 1)
  }

  function toggleTodo(id: number) {
    setTodos((prev) =>
      prev.map((t) => (t.id === id ? { ...t, completed: !t.completed } : t)),
    )
  }

  return (
    <div>
      <h1>Todo List</h1>
      <TodoForm onAdd={handleAdd} />
      <ul>
        {todos.map((todo) => (
          <li key={todo.id}>
            <label>
              <input
                type="checkbox"
                checked={todo.completed}
                onChange={() => toggleTodo(todo.id)}
              />
              <span style={{ textDecoration: todo.completed ? 'line-through' : 'none' }}>
                {todo.text}
              </span>
            </label>
          </li>
        ))}
      </ul>
    </div>
  )
}
