import { test, expect } from '@playwright/test'
import {
  setupAuthenticatedPage,
  createWorkspace,
  setupBoardWithTask,
  setupMemberWithPermissions,
  loginPageAs,
  openBoardProjectDocs,
} from './support/helpers'

async function openProjectDocsModal(page: import('@playwright/test').Page): Promise<void> {
  await page.locator('[data-testid="project-docs-view-all"]').click()
  await expect(page.locator('[data-testid="project-docs-modal"]')).toBeVisible()
}

test.describe('Project board documentation', () => {
  test('shows empty docs state in project info sidebar without upload controls', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project } = await setupBoardWithTask(request, token, workspace.id)

    await openBoardProjectDocs(page, project.id)
    await expect(page.locator('[data-testid="project-info-docs-toggle"]')).toBeVisible()
    await expect(page.locator('[data-testid="project-docs-empty"]')).toBeVisible()
    await expect(page.locator('[data-testid="project-docs-dropzone"]')).not.toBeVisible()
    await expect(page.locator('[data-testid="project-docs-upload-btn"]')).not.toBeVisible()
  })

  test('owner can upload a doc via view all modal and see it in the sidebar', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project } = await setupBoardWithTask(request, token, workspace.id)

    await openBoardProjectDocs(page, project.id)
    await openProjectDocsModal(page)

    const [fileChooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      page.locator('[data-testid="project-docs-upload-btn"]').click(),
    ])
    await fileChooser.setFiles({
      name: 'rules.md',
      mimeType: 'text/markdown',
      buffer: Buffer.from('# Coding Rules\n\nBe excellent to each other.'),
    })

    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid="project-docs-empty"]')).not.toBeVisible()
    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid^="project-doc-file-"]')).toHaveCount(1)

    await page.keyboard.press('Escape')
    await expect(page.locator('[data-testid="project-docs-modal"]')).not.toBeVisible()
    await expect(page.locator('[data-testid="project-docs-section"] [data-testid^="project-doc-file-"]')).toHaveCount(1)
  })

  test('view all opens docs modal with upload zone', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project } = await setupBoardWithTask(request, token, workspace.id)

    await openBoardProjectDocs(page, project.id)
    await openProjectDocsModal(page)

    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid="project-docs-dropzone"]')).toBeVisible()
    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid="project-docs-upload-btn"]')).toBeVisible()
  })

  test('shows upload progress while uploading in modal', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project } = await setupBoardWithTask(request, token, workspace.id)

    await openBoardProjectDocs(page, project.id)
    await openProjectDocsModal(page)

    const [fileChooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      page.locator('[data-testid="project-docs-upload-btn"]').click(),
    ])
    await fileChooser.setFiles({
      name: 'progress.md',
      mimeType: 'text/markdown',
      buffer: Buffer.from('# Progress test'),
    })

    await expect(page.locator('[data-testid="project-docs-upload-progress"]')).toBeVisible()
    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid^="project-doc-file-"]')).toHaveCount(1, { timeout: 10_000 })
  })

  test('rejects unsupported file type without adding it to the list', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project } = await setupBoardWithTask(request, token, workspace.id)

    await openBoardProjectDocs(page, project.id)
    await openProjectDocsModal(page)

    const [fileChooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      page.locator('[data-testid="project-docs-upload-btn"]').click(),
    ])
    await fileChooser.setFiles({
      name: 'bad.exe',
      mimeType: 'application/octet-stream',
      buffer: Buffer.from('not allowed'),
    })

    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid="project-docs-empty"]')).toBeVisible()
    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid^="project-doc-file-"]')).toHaveCount(0)
  })

  test('member without upload permission cannot see upload controls in modal', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const member = await setupMemberWithPermissions(request, ownerToken, project.id, ['view_project'])

    await loginPageAs(page, member.token, member.userObj)
    await openBoardProjectDocs(page, project.id)
    await expect(page.locator('[data-testid="project-docs-upload-btn"]')).not.toBeVisible()
    await expect(page.locator('[data-testid="project-docs-dropzone"]')).not.toBeVisible()

    await openProjectDocsModal(page)
    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid="project-docs-upload-btn"]')).not.toBeVisible()
    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid="project-docs-dropzone"]')).not.toBeVisible()
  })

  test('member with upload permission can upload via modal', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const member = await setupMemberWithPermissions(request, ownerToken, project.id, [
      'view_project',
      'upload_project_doc',
    ])

    await loginPageAs(page, member.token, member.userObj)
    await openBoardProjectDocs(page, project.id)
    await expect(page.locator('[data-testid="project-docs-section"] [data-testid="project-docs-upload-btn"]')).not.toBeVisible()

    await openProjectDocsModal(page)
    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid="project-docs-upload-btn"]')).toBeVisible()

    const [fileChooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      page.locator('[data-testid="project-docs-modal"] [data-testid="project-docs-upload-btn"]').click(),
    ])
    await fileChooser.setFiles({
      name: 'notes.txt',
      mimeType: 'text/plain',
      buffer: Buffer.from('Member uploaded doc'),
    })

    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid="project-docs-empty"]')).not.toBeVisible()
    await expect(page.locator('[data-testid="project-docs-modal"] [data-testid^="project-doc-file-"]')).toHaveCount(1)
  })
})
