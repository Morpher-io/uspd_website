# USPD Project Coding Conventions

## Project Architecture

### Component Organization

1. **Page Components**
   - Pages should be minimal and primarily focused on data fetching and state management
   - Complex UI should be delegated to components
   - Pages should be located in `app/[feature]/page.tsx`

2. **Reusable Components**
   - All reusable UI components should be stored in `components/uspd/`
   - Components should be organized by feature or domain
   - Example structure:
     ```
     components/
     ├── ui/                 # Shadcn UI components
     ├── uspd/               # USPD-specific components
     │   ├── common/         # Shared components across features
     │   ├── stabilizer/     # Stabilizer-specific components
     │   ├── token/          # Token-specific components
     │   └── bridge/         # Bridge-specific components
     └── landingpage/        # Landing page components
     ```

3. **Component Naming**
   - Use PascalCase for component names
   - Suffix with the component type when appropriate (e.g., `StabilizerCard`, `MintForm`)
   - Prefix with feature name for clarity when used across the application

### State Management

1. **Local State**
   - Use React hooks (`useState`, `useReducer`) for component-specific state
   - Keep state as close as possible to where it's used

2. **Contract Interactions**
   - Use wagmi hooks for all blockchain interactions
   - Abstract complex contract interactions into custom hooks in `hooks/contracts/`

### Data Fetching

1. **Contract Data**
   - Use `useReadContracts` for reading data from contracts
   - Handle loading and error states consistently

2. **API Data**
   - Use fetch or axios for API calls
   - Consider SWR or React Query for caching and revalidation

## Coding Standards

### TypeScript

1. **Types**
   - Define interfaces and types in separate files when shared across components
   - Use explicit typing rather than inferred types for function parameters and returns
   - Use `type` for unions, intersections, and mapped types
   - Use `interface` for object shapes that might be extended

2. **Naming**
   - Use descriptive names for variables, functions, and components
   - Use PascalCase for types, interfaces, and components
   - Use camelCase for variables, functions, and instances

### Component Structure

1. **Functional Components**
   - Use functional components with hooks
   - Define prop interfaces at the top of the file
   - Export components as named exports when part of a feature
   - Export as default when the main component of a file

2. **Component Organization**
   ```tsx
   // Import statements
   import { useState } from 'react'
   import { useAccount } from 'wagmi'
   
   // Type definitions
   interface MyComponentProps {
     title: string
     onAction: () => void
   }
   
   // Component definition
   export function MyComponent({ title, onAction }: MyComponentProps) {
     // Hooks
     const [state, setState] = useState(false)
     
     // Event handlers
     const handleClick = () => {
       setState(!state)
       onAction()
     }
     
     // Conditional rendering logic
     if (!title) return null
     
     // Component JSX
     return (
       <div>
         <h1>{title}</h1>
         <button onClick={handleClick}>
           Toggle State: {state ? 'On' : 'Off'}
         </button>
       </div>
     )
   }
   ```

### Error Handling

1. **Contract Interactions**
   - Always handle errors from contract calls
   - Display user-friendly error messages
   - Log detailed errors to console for debugging

2. **Loading States**
   - Always show loading indicators during async operations
   - Disable interactive elements during loading
   - Provide fallback UI for loading states

### Styling

1. **Tailwind CSS**
   - Use Tailwind utility classes for styling
   - Use the `cn()` utility for conditional class names
   - Follow the component design system for consistent UI

2. **Component Design**
   - Use the shadcn/ui components as the foundation
   - Extend or compose shadcn/ui components rather than creating new ones
   - Maintain consistent spacing, typography, and color usage

## Git Workflow

1. **Commits**
   - Use conventional commit messages (feat, fix, docs, style, refactor, test, chore)
   - Keep commits focused on a single change
   - Example: `feat: Add minting functionality for Stabilizer NFTs`

2. **Branches**
   - Use feature branches for new features
   - Use fix branches for bug fixes
   - Name branches with the format: `[type]/[description]`
   - Example: `feature/stabilizer-mint` or `fix/contract-loading`

## Documentation

1. **Code Comments**
   - Comment complex logic or business rules
   - Use JSDoc for functions and components with complex props
   - Keep comments up-to-date with code changes

2. **README**
   - Maintain up-to-date README with setup instructions
   - Document environment variables and configuration
   - Include information about the project structure

3. **USPD Documentation** 
   - Where appropriate either amend or create new documentation in app/docs
   - Follow a consistent and self-explanatory folder structure and add corresponding menu points in docs/_meta.tsx
   - The documentation is generally markdown but with mdx, so it can also contain components
   - It also understands mermaid diagrams and code fences
   - The documentation can be written for technical people as well as crypto natives
   - Bullet points are generally ok, but full short sentences are preferred.

## Testing

1. **Component Testing**
   - Write tests for reusable components
   - Focus on user interactions and expected behavior
   - Mock contract calls and external dependencies

2. **Contract Integration**
   - Test contract interactions with mock providers
   - Verify error handling and edge cases
